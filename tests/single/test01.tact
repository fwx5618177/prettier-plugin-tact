// SPDX-License-Identifier: AGPL-3.0  
// Copyright (C) Microcosm Labs 2024  

import "@stdlib/deploy";

import "./utils/afr";
import "./utils/access_control_single_role";
import "./utils/time";
import "./utils/msgtools";
import "./utils/address";

import "./jetton/jetton_factory";

import "./lbp_math.tact";

import "./pixelswap_messages";
import "./pixelswap_streampool_messages";

/// # Swap contract for Pixelswap TON/Jetton and Jetton/Jetton StreamPool.
///
/// When adding a token pair, a sequential pair id is assigned.
/// This pair id is used to identify the token in swaps.
///
/// This contract is the minter for semi-fungible LP tokens.
/// 3 fee tiers are available: 0.1%, 0.3% and 1%.
///
/// ## Roles
/// **Owner**: Can set the configuration for the unipool. Can set the admin.  
/// Owner should be a multisig wallet.  
/// **Validators**: Can validate pairs. Can create token and pairs disregarding fees and limitations.  
/// Can collect protocol fee to the protocol fee recipient.  
contract PixelswapStreamPool with Deployable, AccessControlSingleRole, JettonFactory {

    /// The minimum amount of tokens that must be in the pool.
    const MIN_TOKENS: Int = 1000;
    /// The minimum amount of liquidity that must be in the pool.
    const MIN_LIQUIDITY: Int = 1000;

    // Storage of AccessControlSingleRole
    owner: Address;
    user_role: map<Address, Bool>;

    // Storage of JettonFactory
    jetton_root_code: Cell;
    jetton_wallet_code: Cell;
    jetton_index: Int as uint32 = 0;

    // Lifecycle
    const metadata_name: String = "Pixelswap StreamPool";
    const metadata_version: Int = 1;

    // Contract Storage
    gas: PoolGasConfig;
    config: PoolConfig;

    settlement: Address;
    exec_id: Int as uint32;

    /// map (token_id => TokenConfig)
    tokens_config: map<Int as uint128, TokenConfig>;
    /// total number of tokens
    tokens_count: Int as uint128 = 0;
    /// `pair_id` is the hash
    /// map (pair_id => pair_config)
    pairs_config: map<Int as uint32, PairConfig>;
    /// map (pair_id => pair_status)
    pairs_status: map<Int as uint32, PairStatus>;
    /// total number of pairs
    pairs_count: Int as uint32 = 0;

    creation_fee_recipient: Address;
    protocol_fee_recipient: Address;

    init(owner: Address, settlement: Address, exec_id: Int,
         config: PoolConfig, gas: PoolGasConfig,
         jetton_root_code: Cell, jetton_wallet_code: Cell
    ) {
        self.settlement = settlement;
        self.exec_id = exec_id;
        self.config = config;
        self.gas = gas;
        self.jetton_root_code = jetton_root_code;
        self.jetton_wallet_code = jetton_wallet_code;
        self.creation_fee_recipient = owner; // TODO: set to creation fee contract
        self.protocol_fee_recipient = owner; // TODO: set to protocol fee contract
        // Initialize AccessControlSingleRole
        self.owner = owner;
        self.grant_role(owner);
        // Initialize token 0 (TON)
        self.tokens_config.set(0, TokenConfig {
            is_validated: true,
            is_active: true,
            token_wallet_address: newAddress(0, 0), // Address 0 implies TON.
            gas_forward_milliton: 0, // Not used
            gas_transfer: 0, // Not used
            query_id: 0, // Not used
        });

        emit(PoolConfigSetEvent { config: config }.toCell());
    }

    // ======================== Internal Messages ========================
    //! 
    //! Internal Messages
    //! ---

    /// PlaceOrder  
    /// Settlement -> **StreamPool** (-> LP::Mint) -> Settlement::OrderExecutionResult  
    /// # Requirements  
    /// - The sender must be the settlement contract.  
    /// - Token1 cannot be TON.  
    /// # Header
    /// The first 2 bits of the header are used to determine the type of order.  
    ///     0b11: Add Liquidity  
    ///     0b01: Swap token1 for token0  
    ///     0b10: Swap token0 for token1  
    ///     0b00: Invalid  
    /// The next bit is used:  
    ///     For Swap: 0: output is exact, 1: input is exact
    ///     For Add Liquidity: 0: unbalanced, 1: balanced
    /// # Add Liquidity
    /// ## `routing_code` layout for Add Liquidity:  
    /// pair_id (u32), ref (ref Cell): lp_amount_out_min (u128)  
    /// ## `header` flags for Add Liquidity:  
    /// token_input (0b11) token_exact (not used) mode (not used)  
    /// # Swap
    /// ## `routing_code` layout for Swap:  
    /// pair_id (u32), routing code (Slice as remaining)  
    /// ## `header` flags for Swap:  
    /// token_input (0b01 or 0b10) token_exact (0b1x = token0 exact, else token1_exact) mode (not used)
    /// # Panics  
    /// If the sender is not the settlement contract.  
    /// If the exec_id does not match.  
    /// If tokens_config for the token does not exist.  
    /// Otherwise AFR.
    receive(msg: PlaceOrder) { // FEAT: handle nested PlaceOrder for atomic swaps and split paths

        require(sender() == self.settlement, "Unauthorized sender"); // afr::allow-trap-irrelevant-path
        // If exec_id doesn't match, the order is routed to the wrong contract. This should never happen.
        require(msg.exec_id == self.exec_id, "Invalid exec_id"); // afr::allow-trap-impossible-path
        if (msg.toCell().afr_require(msg.expiry > now_div4())) { return; } // "Expired order"
        if (msg.toCell().afr_require(msg.token1_id != 0)) { return; } // "Token1 cannot be TON"
        let routing_code: Slice = msg.routing_code;
        if (msg.toCell().afr_require(routing_code.bits() >= 32)) { return; } // "Invalid payload"
        let pair_id: Int = routing_code.loadUint(32);
        // dump("----PlaceOrder pairId----");
        // dump(pair_id);
        let token_ids: Tuple = _math_minmax(msg.token0_id, msg.token1_id);
        let tokens_swapped: Bool = (token_ids.x != msg.token0_id);
        let token_amts: Tuple = tokens_swapped
            ? Tuple { x: msg.token1_amt, y: msg.token0_amt }
            : Tuple { x: msg.token0_amt, y: msg.token1_amt };
        let header: Int = msg.header;
        // dump("----swapped, header----");
        // dump(tokens_swapped);
        // dump(header);
        // dump("----amts----");
        // dump(token_amts.x);
        // dump(token_amts.y);
        let p: PairConfig? = self.pairs_config.get(pair_id);
        if (msg.toCell().afr_require(p != null)) { return; } // "Non-existing pair id"
        let pair_config: PairConfig = p!!;
        if (msg.toCell().afr_require(
            pair_config.token0_id == token_ids.x
            && pair_config.token1_id == token_ids.y
            && pair_config.is_active
            && !pair_config.is_locked
        )) { return; } // "Invalid pair id or pair not active"
        let amountx_to_send: Int = 0;
        let amounty_to_send: Int = 0;
        if (header.token0_is_input() && header.token1_is_input()) { // Add liquidity
            if (msg.toCell().afr_require(self.config.enable_adding_liquidity && pair_config.enable_adding_liquidity && routing_code.refs() >= 1)) { return; } // "Invalid payload"
            let ref_slice: Slice = routing_code.loadRef().asSlice();
            if (msg.toCell().afr_require(ref_slice.bits() >= 128)) { return; } // "Invalid payload"
            let lp_amount_out_min: Int = ref_slice.loadUint(128);
            let res: LiquidityResult = self.add_liquidity(pair_id, token_amts.x, token_amts.y, lp_amount_out_min, header.lp_balanced());
            // dump("----add liquidity result----");
            // dump(res.amount0);
            // dump(res.amount1);
            // calculate amount to send back
            amountx_to_send = token_amts.x - (res.amount0 + res.fee0); // `amountx_to_send > 0` is guaranteed by invariants of add_liquidity
            amounty_to_send = token_amts.y - (res.amount1 + res.fee1); // `amounty_to_send > 0` is guaranteed by invariants of add_liquidity

            // mint LP tokens
            self.mint(pair_id, msg.user, res.liquidity);

            emit(AddLiquidityEvent {
                user: msg.user,
                pair_id,
                amount0: res.amount0,
                amount1: res.amount1,
                lp_amount: res.liquidity,
                fee0: res.fee0,
                fee1: res.fee1,
            }.toCell());
        } else if (header.token0_is_input() != header.token1_is_input()) { // Swap mode
            // FEAT: add routing for swaps to support multiple hops
            if (msg.toCell().afr_require(self.config.enable_trading)) { return; } // "Trading disabled"
            let swap_side: Bool = (header.token0_is_input() != tokens_swapped); // side = token0_is_input XOR tokens_swapped, true if tokenx is input (swap from x to y)
            // let swap_exact_in: Bool = (header.exact_in() != tokens_swapped); // exact_in = exact_in XOR tokens_swapped, true if input token is exact
            let res: SwapResult = SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
            // dump("----swap mode (side, exact_in)----");
            // dump(swap_side);
            // dump(header.exact_in());
            if (header.exact_in()) {
                res = self.swap_exact_amount_in(pair_id, swap_side, token_amts.x, token_amts.y);
            } else {
                res = self.swap_exact_amount_out(pair_id, swap_side, token_amts.x, token_amts.y);
            }
            if (swap_side) { // if tokenx is input
                amountx_to_send = token_amts.x - res.amount_in - res.fee;
                amounty_to_send = res.amount_out;
            } else {
                amountx_to_send = res.amount_out;
                amounty_to_send = token_amts.y - res.amount_in - res.fee;
            }
            // dump("----swap result (in,out,fee)----");
            // dump(res.amount_in);
            // dump(res.amount_out);
            // dump(res.fee);
            // dump("----amount to send (x,y)----");
            // dump(amountx_to_send);
            // dump(amounty_to_send);
            require(amountx_to_send >= 0, "amountx_to_send < 0"); // afr::allow-trap-impossible-path
            require(amounty_to_send >= 0, "amounty_to_send < 0"); // afr::allow-trap-impossible-path

            emit(SwapEvent {
                user: msg.user,
                pair_id,
                side: swap_side,
                amount_in: res.amount_in,
                amount_out: res.amount_out,
                fee: res.fee,
            }.toCell());
        } else { // Neither is input, return with AFR
            if (msg.toCell().afr_require(false)) { return; } // "No input token"
        }

        // Send back the remaining tokens
        let tokenx_config: TokenConfig = self.tokens_config.get(pair_config.token0_id)!!; // afr::allow-trap-impossible-path
        let tokeny_config: TokenConfig = self.tokens_config.get(pair_config.token1_id)!!; // afr::allow-trap-impossible-path
        let c: Builder = beginCell();
        let output_to_ext: Bool = msg.output_to_ext;
        if (!tokenx_config.is_validated || !tokeny_config.is_validated) { // if either config is not validated, set output_to_ext to false
            output_to_ext = false;
        }

        if (output_to_ext) { // When external output is required, it is necessary to check the gas
            let output_to_ext_gas: Int = 0;
            if (pair_config.token0_id != 0 && amountx_to_send > 0) {
                output_to_ext_gas += tokenx_config.gas_forward_milliton + tokenx_config.gas_transfer;
            }
            if (pair_config.token1_id != 0 && amounty_to_send > 0) {
                output_to_ext_gas += tokeny_config.gas_forward_milliton + tokeny_config.gas_transfer;
            }
            // dump("----output_to_ext_gas----");
            // dump(output_to_ext_gas);
            // dump(context().value);
            if (msg.toCell().afr_require(output_to_ext_gas * MILLITON < context().value)) { return; } // The incoming gas is insufficient to cover the external output.
        }

        OrderExecutionResult {
            fund_id: msg.fund_id,
            exec_id: self.exec_id,
            token0_id: pair_config.token0_id,
            token0_amt: amountx_to_send,
            token1_id: pair_config.token1_id,
            token1_amt: amounty_to_send,
            user: msg.user,
            output_to_ext,
            chaining_mode: 0,
            rem: self.build_rem_payload_output_to_ext(output_to_ext, tokenx_config, tokeny_config),
        }.toCell().send_to(self.settlement);
    }

    /// Settlement  withdraws extra gas.  
    /// Anyone EOAs -> Settlement -> **Streampool**.
    /// # Panics
    /// When there is no dust to claim.
    receive(msg: WithdrawDustFromExec) {
        require(sender() == self.settlement, "Unauthenticated sender"); // afr::allow-trap-irrelevant-path
        require(msg.exec_id == self.exec_id, "Invalid fund ID"); // afr::allow-trap-impossible-path
        let dust_to_claim: Int = 0;
        dust_to_claim = myBalance() - context().value - self.gas.storage_reserve * MILLITON;
        if (dust_to_claim > 0) {
            sender().send_ton(dust_to_claim, "dust withdrawn".asComment()); // afr: allow-trap-at-output-boundary
        }
    }

    /// Remove liquidity via Jetton Transfer Notification.  
    /// `query_id`: 32-LSB: pair_id of the target jetton.  
    /// `amount`: amount of jetton transferred.  
    /// `sender`: sender of the jetton.  
    /// `forward_payload`: payload to forward to the Execution contract.  
    /// Data for `forward_payload`:  
    /// **Remove Liquidity**:  
    /// - expiry (u32): Unix epoch div 4  
    /// - fund_id (u32): fund_id to route funds back to.  
    /// - output_to_ext (bool)  
    /// - ref (ref Cell):  
    ///     - amount0_min_out: u128  
    ///     - amount1_min_out: u128  
    /// If the sender is not the jetton wallet address of the specified pair, the jetton is sent back.  
    /// # Panics
    /// If insufficient gas is supplied.  
    /// No AFR error path.
    receive(msg: MSGTOOLS__JettonTransferNotification) {
        require(context().value >= self.gas.transfer_notification_handler * MILLITON, "Insufficient gas"); // afr::allow-trap-at-input-boundary

        let pair_id: Int = msg.query_id & UINT32_MAX;
        let pair_config_option: PairConfig? = self.pairs_config.get(pair_id);
        if (pair_config_option == null) {
            sender().transfer_with_text(msg.sender, msg.amount, ton("0.01"), ton("0.1"), 0, "Pix: E1"); // "Invalid pair id" // TODO: manage gas
            return;
        }
        let pair_config: PairConfig = pair_config_option!!;
        if (pair_config.is_locked) {
            sender().transfer_with_text(msg.sender, msg.amount, ton("0.01"), ton("0.1"), 0, "Pix: E2"); // "Pair is locked" // TODO: manage gas
            return;
        }
        let user: Address = msg.sender;

        if (sender() == self.jetton_wallet_address_of(pair_id, myAddress())) { // If tx comes from my LP wallet address, remove liquidity
            // decode forward_payload slice
            let payload: Slice = msg.forward_payload;
            if (payload.bits() < 65 || payload.refs() < 1) {
                sender().transfer_with_text(user, msg.amount, ton("0.01"), ton("0.1"), 0, "Pix: E3"); // "Decode failed"
                return;
            }
            let expiry: Int = payload.loadUint(32);
            let fund_id: Int = payload.loadUint(32);
            let output_to_ext: Bool = payload.loadUint(1) == 1;
            let ref_0: Slice = payload.loadRef().asSlice();
            if (ref_0.bits() < 256) {
                sender().transfer_with_text(user, msg.amount, ton("0.01"), ton("0.1"), 0, "Pix: E3");
                return;
            }
            let amount0_min_out: Int = ref_0.loadUint(128);
            let amount1_min_out: Int = ref_0.loadUint(128);

            let to: Address = sender();
            let res: LiquidityResult = self.remove_liquidity(msg.query_id, msg.amount, amount0_min_out, amount1_min_out);
            if (expiry <= now_div4() || res.liquidity == 0) {
                sender().transfer_with_text(user, msg.amount, ton("0.01"), ton("0.1"), 0, "Pix: E4"); // "Invalid expiry or liquidity"
            } else {
                // burn LP tokens
                self.burn(pair_id, res.liquidity);

                // transfer ton/jetton
                let token0_config: TokenConfig = self.tokens_config.get(pair_config.token0_id)!!;
                let token1_config: TokenConfig = self.tokens_config.get(pair_config.token1_id)!!;
                let c: Builder = beginCell();
                if (!token0_config.is_validated || !token1_config.is_validated) { // if either config is not validated, set output_to_ext to false
                    output_to_ext = false;
                }
                OrderExecutionResult {
                    fund_id,
                    exec_id: self.exec_id,
                    token0_id: pair_config.token0_id,
                    token0_amt: res.amount0,
                    token1_id: pair_config.token1_id,
                    token1_amt: res.amount1,
                    user: msg.sender,
                    output_to_ext,
                    chaining_mode: 0,
                    rem: self.build_rem_payload_output_to_ext(output_to_ext, token0_config, token1_config),
                }.toCell().send_to(self.settlement);

                emit(RemoveLiquidityEvent {
                    user: msg.sender,
                    pair_id: msg.query_id,
                    amount0: res.amount0,
                    amount1: res.amount1,
                    lp_amount: res.liquidity,
                }.toCell());
            }
        } else { // sender not authenticated
            sender().transfer_with_text(user, msg.amount, ton("0.01"), ton("0.1"), 0, "Pix: E5"); // "Invalid sender" // TODO: manage gas
        }
    }

    /// Silently accept JettonExcesses
    receive(msg: MSGTOOLS__JettonExcesses) {}

    // ======================== User Meessages ========================
    //! 
    //! User Messages
    //! ---

    /// Create a new token.
    receive(msg: CreateToken) {
        require(self.has_role(sender()) || context().value >= self.config.token_creation_fee * MILLITON, "Incorrect token creation fee"); // afr::allow-trap-at-input-boundary
        require(self.has_role(sender()) || self.config.enable_token_creation, "Pair creation not possible"); // afr::allow-trap-at-input-boundary
        require(self.tokens_config.get(msg.token_id) == null, "Token already exists"); // afr::allow-trap-at-input-boundary
        self.tokens_count += 1;
        self.tokens_config.set(msg.token_id, TokenConfig {
            is_validated: false,
            is_active: true, // by default, tokens are active and can be used to create pairs without validation
            token_wallet_address: newAddress(0, 0x04), // Dummy address. Address 0 implies TON so we avoid that.
            gas_forward_milliton: self.gas.default_token_forward_milliton,
            gas_transfer: self.gas.default_token_transfer,
            query_id: 0,
        });
        emit(TokenCreatedEvent { token_id: msg.token_id }.toCell());
        self.creation_fee_recipient.send_ton(self.config.token_creation_fee * MILLITON, null);
    }

    /// Create a new trading pair.  
    /// Developers can monitor the event to get `pair_id`, then use `pair_id` to get `pair_config`.  
    /// `token0_address` `token1_address `fee_bps` `weight0` and can be used to query for `pair_id`.  
    receive(msg: CreateTradingPair) {
        require(self.has_role(sender()) || context().value >= (self.config.pair_creation_fee + self.gas.pair_creation) * MILLITON, "Incorrect pair creation fee"); // afr::allow-trap-at-input-boundary
        require(self.has_role(sender()) || self.config.enable_pair_creation, "Pair creation not possible"); // afr::allow-trap-at-input-boundary
        require(msg.token0_id < msg.token1_id, "Token0 must have a lower address"); // afr::allow-trap-at-input-boundary
        require(msg.fee_bps >= 10 && msg.fee_bps <= 250, "Fee must be between 0.10% and 2.50%"); // afr::allow-trap-at-input-boundary
        require(msg.weight0 > 0 && msg.weight0 < 100, "Weight0t0 must be between 1% and 99%"); // afr::allow-trap-at-input-boundary

        if (msg.token0_id != 0) {
            let token0_config: TokenConfig = self.tokens_config.get(msg.token0_id)!!; // afr::allow-trap-at-input-boundary
            require(token0_config.is_active, "Token0 is not active"); // afr::allow-trap-at-input-boundary
        }
        let token1_config: TokenConfig = self.tokens_config.get(msg.token1_id)!!;
        require(token1_config.is_active, "Token1 is not active"); // afr::allow-trap-at-input-boundary

        let pair_id: Int = self.pair_id(msg.token0_id, msg.token1_id, msg.fee_bps, msg.weight0);
        require(self.pairs_config.get(pair_id) == null, "Pair already exists"); // afr::allow-trap-at-input-boundary
        self.pairs_count += 1;

        let pair_config: PairConfig = PairConfig {
            is_active: false,
            is_locked: false,
            enable_adding_liquidity: msg.enable_adding_liquidity,
            enable_onchain_oracle: false,
            token0_id: msg.token0_id,
            token1_id: msg.token1_id,
            fee_bps: msg.fee_bps,
            weight0: msg.weight0,
            oracle_address: newAddress(0, 0),
            creator_address: sender(),
        };
        self.pairs_config.set(pair_id, pair_config);
        self.pairs_status.set(pair_id, PairStatus { reserve0: 0, reserve1: 0, lp_supply: 0, token0_fees_payable: 0, token1_fees_payable: 0 });

        self.create_jetton_root(pair_id);
        emit(PairCreatedEvent { pair_id: pair_id }.toCell());
        self.creation_fee_recipient.send_ton(self.config.pair_creation_fee * MILLITON, null);
    }

    // ======================== Admin Messages ========================
    //! 
    //! Admin Messages
    //! ---

    receive(msg: SetPoolConfig) {
        self.requireOwner(); // afr::allow-trap-at-input-boundary
        require(self.config.toCell().hash() != msg.config.toCell().hash(), "No changes"); // afr::allow-trap-at-input-boundary
        self.config = msg.config;
        emit(PoolConfigSetEvent { config: msg.config }.toCell());
        refund_gas();
    }

    receive(msg: SetPoolGasConfig) {
        self.requireOwner(); // afr::allow-trap-at-input-boundary
        require(self.gas.toCell().hash() != msg.gas.toCell().hash(), "No changes"); // afr::allow-trap-at-input-boundary
        self.gas = msg.gas;
        refund_gas();
    }

    receive(msg: ValidateToken) {
        self.require_role(sender()); // afr::allow-trap-at-input-boundary
        let token_config: TokenConfig = self.tokens_config.get(msg.token_id)!!; // afr::allow-trap-at-input-boundary
        require(!token_config.is_validated, "Token already validated"); // afr::allow-trap-at-input-boundary
        token_config.is_validated = true;
        token_config.token_wallet_address = msg.token_wallet_address;
        self.tokens_config.set(msg.token_id, token_config);
    }

    receive(msg: SetTokenActiveStatus) {
        self.requireOwner(); // afr::allow-trap-at-input-boundary
        let token_config: TokenConfig = self.tokens_config.get(msg.token_id)!!; // afr::allow-trap-at-input-boundary
        require(token_config.is_active != msg.active, "No changes"); // afr::allow-trap-at-input-boundary
        token_config.is_active = msg.active;
        self.tokens_config.set(msg.token_id, token_config);
    }

    receive(msg: SetTokenGas) {
        self.requireOwner(); // afr::allow-trap-at-input-boundary
        let token_config: TokenConfig = self.tokens_config.get(msg.token_id)!!; // afr::allow-trap-at-input-boundary
        require(token_config.gas_forward_milliton != msg.gas_forward_milliton
            || token_config.gas_transfer != msg.gas_transfer
            || token_config.query_id != msg.query_id, "No changes"); // afr::allow-trap-at-input-boundary
        token_config.gas_forward_milliton = msg.gas_forward_milliton;
        token_config.gas_transfer = msg.gas_transfer;
        token_config.query_id = msg.query_id;
        self.tokens_config.set(msg.token_id, token_config);
    }

    /// Validates a new pair.  
    /// Admin can call this to validate a pair creation request.
    receive(msg: SetPairActiveStatus) {
        self.requireOwner(); // afr::allow-trap-at-input-boundary
        let pair_config: PairConfig = self.pairs_config.get(msg.pair_id)!!; // afr::allow-trap-at-input-boundary
        require(pair_config.is_active != msg.active, "No changes"); // afr::allow-trap-at-input-boundary
        pair_config.is_active = msg.active;
        self.pairs_config.set(msg.pair_id, pair_config);
    }

    /// Locks/unlocks a pair.  
    /// Admin can call this to lock/unlock a pair.
    receive(msg: SetPairLockStatus) {
        self.requireOwner(); // afr::allow-trap-at-input-boundary
        let pair_config: PairConfig = self.pairs_config.get(msg.pair_id)!!; // afr::allow-trap-at-input-boundary
        require(pair_config.is_locked != msg.lock, "No changes"); // afr::allow-trap-at-input-boundary
        pair_config.is_locked = msg.lock;
        self.pairs_config.set(msg.pair_id, pair_config);
    }

    /// Set enable_adding_liquidity for a pair.
    receive(msg: SetPairEnableAddingLiquidityFlag) {
        self.requireOwner(); // afr::allow-trap-at-input-boundary
        let pair_config: PairConfig = self.pairs_config.get(msg.pair_id)!!; // afr::allow-trap-at-input-boundary
        require(pair_config.enable_adding_liquidity != msg.enable, "No changes"); // afr::allow-trap-at-input-boundary
        pair_config.enable_adding_liquidity = msg.enable;
        self.pairs_config.set(msg.pair_id, pair_config);
    }

    /// Collect protocol fee to the protocol fee recipient.  
    /// Uses `OrderExecutionResult` to send the collected fees to the protocol fee recipient.  
    receive(msg: CollectProtocolFee) {
        self.require_role(sender()); // afr::allow-trap-at-input-boundary
        let pair_config: PairConfig = self.pairs_config.get(msg.pair_id)!!; // afr::allow-trap-at-input-boundary
        let pair_status: PairStatus = self.pairs_status.get(msg.pair_id)!!; // afr::allow-trap-at-input-boundary
        let token0_config: TokenConfig = self.tokens_config.get(pair_config.token0_id)!!; // afr::allow-trap-at-input-boundary
        let token1_config: TokenConfig = self.tokens_config.get(pair_config.token1_id)!!; // afr::allow-trap-at-input-boundary

        OrderExecutionResult {
            fund_id: msg.fund_id,
            exec_id: self.exec_id,
            token0_id: pair_config.token0_id,
            token0_amt: pair_status.token0_fees_payable,
            token1_id: pair_config.token1_id,
            token1_amt: pair_status.token1_fees_payable,
            user: self.protocol_fee_recipient,
            output_to_ext: true,
            chaining_mode: 0,
            rem: self.build_rem_payload_output_to_ext(true, token0_config, token1_config),
        }.toCell().send_to(self.settlement);
        pair_status.token0_fees_payable = 0;
        pair_status.token1_fees_payable = 0;
        self.pairs_status.set(msg.pair_id, pair_status);
    }

    // ======================== Internal Functions ========================
    //! 
    //! Internal Functions
    //! ---

    // Return the current weight of the pair using linear extrapolation.
    // If `side` is true, the weight of token0 is returned.
    // If `side` is false, the weight of token1 is returned. (1 - weight0)
    // inline fun current_weight(config: PairConfig, side: Bool): Int {
    //     if (config.weight0_t1 == 0) {
    //         return side.cond_int(config.weight0, UINT16_MAX - config.weight0);
    //     } else {
    //         let t: Int = now_div4();
    //         if (t >= config.t1) {
    //             return side.cond_int(config.weight0_t1, UINT16_MAX - config.weight0_t1);
    //         } else if (t <= config.t0) {
    //             return side.cond_int(config.weight0, UINT16_MAX - config.weight0);
    //         } else {
    //             let w: Int = config.weight0 + _math_muldiv(config.weight0_t1 - config.weight0, t - config.t0, config.t1 - config.t0);
    //             return side.cond_int(w, UINT16_MAX - w);
    //         }
    //     }
    // }

    fun build_rem_payload_output_to_ext(output_to_ext: Bool, token0_config: TokenConfig, token1_config: TokenConfig): Slice {
        if (output_to_ext) {
            let c: Builder = beginCell();
            c = c.storeAddress(token0_config.token_wallet_address);
            c = c.storeAddress(token1_config.token_wallet_address);
            c = c.storeUint(token0_config.gas_forward_milliton, 32);
            c = c.storeUint(token1_config.gas_forward_milliton, 32);
            c = c.storeUint(token0_config.gas_transfer, 32);
            c = c.storeUint(token1_config.gas_transfer, 32);
            c = c.storeUint(token0_config.query_id, 64);
            c = c.storeUint(token1_config.query_id, 64);
            return beginCell().storeRef(c.endCell()).asSlice();
        } else {
            return emptySlice();
        }
    }

    /// Internal method for swapping without security checks.  
    /// `side` is true if token0 is the input token.  
    /// Returns 0 if the swap failed.  
    /// # Panics  
    /// Never.  
    fun swap_exact_amount_in(pair_id: Int, side: Bool, amount0: Int, amount1: Int): SwapResult {
        let p: PairStatus? = self.pairs_status.get(pair_id);
        let res: SwapResult = SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
        if (p == null) {
            return res;
        }
        let pair_status: PairStatus = p!!;
        let pair_config: PairConfig = self.pairs_config.get(pair_id)!!;
        if (!pair_config.is_active || pair_config.is_locked) {
            return SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
        }
        // dump("----swap_exact_amount_in (amount0, amount1)----");
        // dump(amount0);
        // dump(amount1);
        // dump("reserves");
        // dump(pair_status.reserve0);
        // dump(pair_status.reserve1);
        if (side) {
            res = calc_swap_exact_amount_in(amount0, pair_status.reserve0, pair_status.reserve1, pair_config.fee_bps, 5000);
            // dump("----swap_exact_amount_in side=true----");
            // dump(res.amount_in);
            // dump(res.amount_out);
            pair_status.reserve0 += res.amount_in;
            pair_status.reserve1 -= res.amount_out; // reserve1 >= res.amount_out is guaranteed by invariants of calc_swap_exact_amount_in
            pair_status.token0_fees_payable += res.fee; // TODO: split fee between protocol and liquidity providers (add to reserve)
            if (res.amount_out < amount1 || pair_status.reserve1 < self.MIN_TOKENS) {
                return SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
            }
        } else {
            res = calc_swap_exact_amount_in(amount1, pair_status.reserve1, pair_status.reserve0, pair_config.fee_bps, 5000);
            // dump("----swap_exact_amount_in side=false----");
            // dump(res.amount_in);
            // dump(res.amount_out);
            pair_status.reserve1 += res.amount_in;
            pair_status.reserve0 -= res.amount_out; // reserve0 >= res.amount_out is guaranteed by invariants of calc_swap_exact_amount_in
            pair_status.token1_fees_payable += res.fee;
            if (res.amount_out < amount0 || pair_status.reserve0 < self.MIN_TOKENS) {
                return SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
            }
        }
        self.pairs_status.set(pair_id, pair_status);
        return res;
    }

    /// Internal method for swapping without security checks.  
    /// `side` is true if token0 is the input token.  
    /// Returns 0 if the swap failed.  
    /// # Panics  
    /// Never.  
    fun swap_exact_amount_out(pair_id: Int, side: Bool, amount0: Int, amount1: Int): SwapResult {
        let p: PairStatus? = self.pairs_status.get(pair_id);
        let res: SwapResult = SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
        if (p == null) {
            return res;
        }
        let pair_status: PairStatus = p!!;
        let pair_config: PairConfig = self.pairs_config.get(pair_id)!!;
        if (!pair_config.is_active || pair_config.is_locked) {
            return SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
        }
        // dump("----swap_exact_amount_out (amount0, amount1)----");
        // dump(amount0);
        // dump(amount1);
        // dump("reserves");
        // dump(pair_status.reserve0);
        // dump(pair_status.reserve1);
        if (side) { // token0 -> token1
            res = calc_swap_exact_amount_out(amount1, pair_status.reserve0, pair_status.reserve1, pair_config.fee_bps, 5000);
            // dump("----swap_exact_amount_out side=true----");
            // dump(res.amount_in);
            // dump(res.amount_out);
            pair_status.reserve0 += res.amount_in;
            pair_status.reserve1 -= res.amount_out; // reserve1 >= res.amount_out is guaranteed by invariants of calc_swap_exact_amount_out
            pair_status.token0_fees_payable += res.fee;
            if (res.amount_in > amount0 || pair_status.reserve1 < self.MIN_TOKENS) {
                return SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
            }
        } else { // token0 <- token1
            res = calc_swap_exact_amount_out(amount0, pair_status.reserve1, pair_status.reserve0, pair_config.fee_bps, 5000);
            // dump("----swap_exact_amount_out side=false----");
            // dump(res.amount_in);
            // dump(res.amount_out);
            pair_status.reserve1 += res.amount_in;
            pair_status.reserve0 -= res.amount_out; // reserve0 >= res.amount_out is guaranteed by invariants of calc_swap_exact_amount_out
            pair_status.token1_fees_payable += res.fee;
            if (res.amount_in > amount1 || pair_status.reserve0 < self.MIN_TOKENS) {
                return SwapResult { amount_in: 0, amount_out: 0, fee: 0 };
            }
        }
        self.pairs_status.set(pair_id, pair_status);
        return res;
    }

    /// Internal method for adding liquidity without security checks.  
    /// # Panics  
    /// Never.  
    fun add_liquidity(pair_id: Int, token0_amt: Int, token1_amt: Int, lp_amount_out_min: Int, lp_balanced: Bool): LiquidityResult {
        let p: PairStatus? = self.pairs_status.get(pair_id);
        let res: LiquidityResult = LiquidityResult { amount0: 0, amount1: 0, liquidity: 0, fee0: 0, fee1: 0 };
        if (p == null) {
            return res;
        }
        let pair_status: PairStatus = p!!;
        if (lp_balanced) {
            res = calc_add_lp_balanced(token0_amt, token1_amt, pair_status.reserve0, pair_status.reserve1, pair_status.lp_supply, 0, 5000);
        } else {
            res = calc_add_lp_unbalanced(token0_amt, token1_amt, pair_status.reserve0, pair_status.reserve1, pair_status.lp_supply, 0, 5000);
        }
        // if slippage too high, abort
        if (res.liquidity < lp_amount_out_min || res.liquidity < self.MIN_LIQUIDITY) {
            res = LiquidityResult { amount0: 0, amount1: 0, liquidity: 0, fee0: 0, fee1: 0 };
        }
        // update pair status
        pair_status.reserve0 += res.amount0;
        pair_status.reserve1 += res.amount1;
        pair_status.lp_supply += res.liquidity;
        self.pairs_status.set(pair_id, pair_status);
        return res;
    }

    /// Internal method for removing liquidity without security checks.  
    /// # Panics  
    /// Never.  
    fun remove_liquidity(pair_id: Int, lp_amount: Int, amount0_min_out: Int, amount1_min_out: Int): LiquidityResult {
        let p: PairStatus? = self.pairs_status.get(pair_id);
        let res: LiquidityResult = LiquidityResult { amount0: 0, amount1: 0, liquidity: 0, fee0: 0, fee1: 0 };
        if (p == null) {
            return res;
        }
        let pair_status: PairStatus = p!!;
        res = calc_remove_lp(lp_amount, pair_status.reserve0, pair_status.reserve1, pair_status.lp_supply, 0, 5000);
        if (res.amount0 < amount0_min_out || res.amount1 < amount1_min_out || pair_status.lp_supply - res.liquidity < self.MIN_LIQUIDITY) {
            res = LiquidityResult { amount0: 0, amount1: 0, liquidity: 0, fee0: 0, fee1: 0 };
        }
        // update pair status
        pair_status.reserve0 -= res.amount0; // `reserve0 >= res.amount0` is guaranteed by invariants of calc_remove_lp
        pair_status.reserve1 -= res.amount1; // `reserve1 >= res.amount1` is guaranteed by invariants of calc_remove_lp
        pair_status.lp_supply -= res.liquidity; // `lp_supply >= res.liquidity` is guaranteed by invariants of calc_remove_lp
        self.pairs_status.set(pair_id, pair_status);
        return res;
    }

    // ======================== Getters ========================
    //! 
    //! Getter Functions
    //! ---

    get fun config(): PoolConfig {
        return self.config;
    }

    get fun number_pairs(): Int {
        return self.pairs_count;
    }

    get fun pair_id(token0_id: Int, token1_id: Int, fee_bps: Int, weight0: Int): Int {
        let token_ids: Tuple = _math_minmax(token0_id, token1_id);
        return beginCell()
            .storeUint(token_ids.x, 128)
            .storeUint(token_ids.y, 128)
            .storeUint(fee_bps, 8)
            .storeUint(weight0, 8)
            .endCell().hash() & UINT32_MAX;
    }

    get fun pair_config(index: Int): PairConfig? {
        return self.pairs_config.get(index);
    }

    get fun pair_status(index: Int): PairStatus? {
        return self.pairs_status.get(index);
    }

    get fun gas_config(): PoolGasConfig {
        return self.gas;
    }

    /// Calculate the amount of token output for an exact amount of tokens input.  
    /// `amount_in`: amount of tokens sent.  
    /// `pair_id`: pair id.  
    /// `side`: true if token0 is the input token.
    get fun amount_out_for_exact_amount_in(amount_in: Int, pair_id: Int, side: Bool): SwapResult {
        let pair_status: PairStatus = self.pairs_status.get(pair_id)!!;
        let pair_config: PairConfig = self.pairs_config.get(pair_id)!!;
        if (side) {
            return calc_swap_exact_amount_in(amount_in, pair_status.reserve0, pair_status.reserve1, pair_config.fee_bps, 5000);
        } else {
            return calc_swap_exact_amount_in(amount_in, pair_status.reserve1, pair_status.reserve0, pair_config.fee_bps, 5000);
        }
    }

    /// Calculate the amount of token input for an exact amount of tokens output.
    /// `amount_out`: amount of tokens received.
    /// `pair_id`: pair id.
    /// `side`: true if token0 is the input token.
    get fun amount_in_for_exact_amount_out(amount_out: Int, pair_id: Int, side: Bool): SwapResult {
        let pair_status: PairStatus = self.pairs_status.get(pair_id)!!;
        let pair_config: PairConfig = self.pairs_config.get(pair_id)!!;
        if (side) {
            return calc_swap_exact_amount_out(amount_out, pair_status.reserve0, pair_status.reserve1, pair_config.fee_bps, 5000);
        } else {
            return calc_swap_exact_amount_out(amount_out, pair_status.reserve1, pair_status.reserve0, pair_config.fee_bps, 5000);
        }
    }

    /// Calculate the amount of LP tokens to mint for adding liquidity.  
    /// `amount0`: amount of token0 to add.  
    /// `amount1`: amount of token1 to add.  
    /// `pair_id`: pair id.  
    /// `lp_balanced`: true if the LP tokens should be minted in a balanced way.  
    /// Returns a `LiquidityResult`.
    get fun lp_amount_for_amounts_in(amount0: Int, amount1: Int, pair_id: Int, lp_balanced: Bool): LiquidityResult {
        let pair_status: PairStatus = self.pairs_status.get(pair_id)!!;
        if (lp_balanced) {
            return calc_add_lp_balanced(amount0, amount1, pair_status.reserve0, pair_status.reserve1, pair_status.lp_supply, 0, 5000);
        } else {
            return calc_add_lp_unbalanced(amount0, amount1, pair_status.reserve0, pair_status.reserve1, pair_status.lp_supply, 0, 5000);
        }
    }

    /// Calculate the amount of token0 and token1 to receive for removing liquidity.
    get fun token_amounts_for_lp_in(lp_amount: Int, pair_id: Int): LiquidityResult {
        let pair_status: PairStatus = self.pairs_status.get(pair_id)!!;
        return calc_remove_lp(lp_amount, pair_status.reserve0, pair_status.reserve1, pair_status.lp_supply, 0, 5000);
    }

    get fun tokens_config(token_id: Int): TokenConfig? {
        return self.tokens_config.get(token_id);
    }

    get fun tokens_count(): Int {
        return self.tokens_count;
    }

    get fun exec_id(): Int {
        return self.exec_id;
    }

    // get fun simulatePlaceOrder(msg: PlaceOrder): OrderSimulationResult {
    //     let routing_code: Slice = msg.routing_code;
    //     let pair_id: Int = routing_code.loadUint(32);
    //     let header: Int = msg.header;
    //     let pair_config: PairConfig = self.pairs_config.get(pair_id)!!;
    //     let result: OrderSimulationResult = OrderSimulationResult{amount0_diff: 0, amount1_diff: 0, liquidity_diff: 0};
    //     if (header.token0_is_input() && header.token1_is_input()) { // Add liquidity
    //         let lp_balanced: Bool = (routing_code.loadUint(1) != 0);
    //         let ref_slice: Slice = routing_code.loadRef().asSlice();
    //         let lp_amount_out_min: Int = ref_slice.loadUint(128);
    //         let res: LiquidityResult = self.add_liquidity(pair_id, msg.token0_amt, msg.token1_amt, lp_amount_out_min, lp_balanced);
    //         result = OrderSimulationResult{amount0_diff: - res.amount0, amount1_diff: - res.amount1, liquidity_diff: res.liquidity};
    //     } else if (header.token0_is_input() && !header.token1_is_input()) { // Swap token0 for token1
    //         let res: SwapResult = SwapResult{amount_in: 0, amount_out: 0, fee: 0};
    //         if (header.token0_is_exact()) {
    //             res = self.swap_exact_amount_in(pair_id, true, msg.token0_amt, msg.token1_amt);
    //         } else {
    //             res = self.swap_exact_amount_out(pair_id, true, msg.token0_amt, msg.token1_amt);
    //         }
    //         result = OrderSimulationResult{amount0_diff: - res.amount_in, amount1_diff: res.amount_out, liquidity_diff: 0};
    //     } else if (header.token1_is_input() && !header.token0_is_input()) { // Swap token1 for token0
    //         let res: SwapResult = SwapResult{amount_in: 0, amount_out: 0, fee: 0};
    //         if (header.token1_is_exact()) {
    //             res = self.swap_exact_amount_in(pair_id, false, msg.token1_amt, msg.token0_amt);
    //         } else {
    //             res = self.swap_exact_amount_out(pair_id, false, msg.token1_amt, msg.token0_amt);
    //         }
    //         result = OrderSimulationResult{amount0_diff: res.amount_out, amount1_diff: - res.amount_in, liquidity_diff: 0};
    //     }
    //     return result;
    // }

    // ==================== Lifecycle ====================
    //! 
    //! Lifecycle Functions
    //! ---

    // Fund the contract
    receive("fund gas") {}
    receive("refund gas") {}

    get fun balance(): Int {
        return myBalance();
    }

    get fun metadata_name(): String {
        return self.metadata_name;
    }

    get fun metadata_version(): Int {
        return self.metadata_version;
    }
}
