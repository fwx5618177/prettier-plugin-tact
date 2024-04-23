declare module "tact-format" {
    type TypeOrigin = "stdlib" | "user";

    type ASTPrimitive = {
        kind: "primitive";
        origin: TypeOrigin;
        id: number;
        name: string;
        ref: ASTRef;
    };
    
    //
    // Values
    //
    
    type ASTNumber = {
        kind: "number";
        id: number;
        value: bigint;
        ref: ASTRef;
    };
    
    type ASTID = {
        kind: "id";
        id: number;
        value: string;
        ref: ASTRef;
    };
    
    type ASTBoolean = {
        kind: "boolean";
        id: number;
        value: boolean;
        ref: ASTRef;
    };
    
    type ASTString = {
        kind: "string";
        id: number;
        value: string;
        ref: ASTRef;
    };
    
    type ASTNull = {
        kind: "null";
        id: number;
        ref: ASTRef;
    };
    
    type ASTLvalueRef = {
        kind: "lvalue_ref";
        id: number;
        name: string;
        ref: ASTRef;
    };
    
    //
    // Types
    //
    
    type ASTTypeRefSimple = {
        kind: "type_ref_simple";
        id: number;
        name: string;
        optional: boolean;
        ref: ASTRef;
    };
    
    type ASTTypeRefMap = {
        kind: "type_ref_map";
        id: number;
        key: string;
        keyAs: string | null;
        value: string;
        valueAs: string | null;
        ref: ASTRef;
    };
    
    type ASTTypeRefBounced = {
        kind: "type_ref_bounced";
        id: number;
        name: string;
        ref: ASTRef;
    };
    
    type ASTTypeRef = ASTTypeRefSimple | ASTTypeRefMap | ASTTypeRefBounced;
    
    //
    // Expressions
    //
    
    type ASTOpBinary = {
        kind: "op_binary";
        id: number;
        op:
            | "+"
            | "-"
            | "*"
            | "/"
            | "!="
            | ">"
            | "<"
            | ">="
            | "<="
            | "=="
            | "&&"
            | "||"
            | "%"
            | "<<"
            | ">>"
            | "&"
            | "|"
            | "^";
        left: ASTExpression;
        right: ASTExpression;
        ref: ASTRef;
    };
    
    type ASTOpUnary = {
        kind: "op_unary";
        id: number;
        op: "+" | "-" | "!" | "!!";
        right: ASTExpression;
        ref: ASTRef;
    };
    
    type ASTOpField = {
        kind: "op_field";
        id: number;
        src: ASTExpression;
        name: string;
        ref: ASTRef;
    };
    
    type ASTOpCall = {
        kind: "op_call";
        id: number;
        src: ASTExpression;
        name: string;
        args: ASTExpression[];
        ref: ASTRef;
    };
    
    type ASTOpCallStatic = {
        kind: "op_static_call";
        id: number;
        name: string;
        args: ASTExpression[];
        ref: ASTRef;
    };
    
    type ASTOpNew = {
        kind: "op_new";
        id: number;
        type: string;
        args: ASTNewParameter[];
        ref: ASTRef;
    };
    
    type ASTNewParameter = {
        kind: "new_parameter";
        id: number;
        name: string;
        exp: ASTExpression;
        ref: ASTRef;
    };
    
    type ASTInitOf = {
        kind: "init_of";
        id: number;
        name: string;
        args: ASTExpression[];
        ref: ASTRef;
    };
    
    type ASTConditional = {
        kind: "conditional";
        id: number;
        condition: ASTExpression;
        thenBranch: ASTExpression;
        elseBranch: ASTExpression;
        ref: ASTRef;
    };
    
    //
    // Program
    //
    
    type ASTProgram = {
        kind: "program";
        id: number;
        entries: (
            | ASTStruct
            | ASTContract
            | ASTPrimitive
            | ASTFunction
            | ASTNativeFunction
            | ASTTrait
            | ASTProgramImport
            | ASTConstant
        )[];
    };
    
    type ASTProgramImport = {
        kind: "program_import";
        id: number;
        path: ASTString;
        ref: ASTRef;
    };
    
    type ASTStruct = {
        kind: "def_struct";
        origin: TypeOrigin;
        id: number;
        name: string;
        message: boolean;
        prefix: number | null;
        fields: ASTField[];
        ref: ASTRef;
    };
    
    type ASTTrait = {
        kind: "def_trait";
        origin: TypeOrigin;
        id: number;
        name: string;
        traits: ASTString[];
        attributes: ASTContractAttribute[];
        declarations: (ASTField | ASTFunction | ASTReceive | ASTConstant)[];
        ref: ASTRef;
    };
    
    type ASTField = {
        kind: "def_field";
        id: number;
        name: string;
        type: ASTTypeRef;
        init: ASTExpression | null;
        as: string | null;
        ref: ASTRef;
    };
    
    type ASTConstant = {
        kind: "def_constant";
        id: number;
        name: string;
        type: ASTTypeRef;
        value: ASTExpression | null;
        attributes: ASTConstantAttribute[];
        ref: ASTRef;
    };
    
    type ASTConstantAttribute =
        | { type: "virtual"; ref: ASTRef }
        | { type: "overrides"; ref: ASTRef }
        | { type: "abstract"; ref: ASTRef };
    
    type ASTContractAttribute = {
        type: "interface";
        name: ASTString;
        ref: ASTRef;
    };
    
    type ASTContract = {
        kind: "def_contract";
        origin: TypeOrigin;
        id: number;
        name: string;
        traits: ASTString[];
        attributes: ASTContractAttribute[];
        declarations: (
            | ASTField
            | ASTFunction
            | ASTInitFunction
            | ASTReceive
            | ASTConstant
        )[];
        ref: ASTRef;
    };
    
    type ASTArgument = {
        kind: "def_argument";
        id: number;
        name: string;
        type: ASTTypeRef;
        ref: ASTRef;
    };
    
    type ASTFunctionAttribute =
        | { type: "get"; ref: ASTRef }
        | { type: "mutates"; ref: ASTRef }
        | { type: "extends"; ref: ASTRef }
        | { type: "virtual"; ref: ASTRef }
        | { type: "abstract"; ref: ASTRef }
        | { type: "overrides"; ref: ASTRef }
        | { type: "inline"; ref: ASTRef };
    
    type ASTFunction = {
        kind: "def_function";
        origin: TypeOrigin;
        id: number;
        attributes: ASTFunctionAttribute[];
        name: string;
        return: ASTTypeRef | null;
        args: ASTArgument[];
        statements: ASTStatement[] | null;
        ref: ASTRef;
    };
    
    type ASTReceive = {
        kind: "def_receive";
        id: number;
        selector:
            | {
                  kind: "internal-simple";
                  arg: ASTArgument;
              }
            | {
                  kind: "internal-fallback";
              }
            | {
                  kind: "internal-comment";
                  comment: ASTString;
              }
            | {
                  kind: "bounce";
                  arg: ASTArgument;
              }
            | {
                  kind: "external-simple";
                  arg: ASTArgument;
              }
            | {
                  kind: "external-fallback";
              }
            | {
                  kind: "external-comment";
                  comment: ASTString;
              };
        statements: ASTStatement[];
        ref: ASTRef;
    };
    
    type ASTNativeFunction = {
        kind: "def_native_function";
        origin: TypeOrigin;
        id: number;
        attributes: ASTFunctionAttribute[];
        name: string;
        nativeName: string;
        return: ASTTypeRef | null;
        args: ASTArgument[];
        ref: ASTRef;
    };
    
    type ASTInitFunction = {
        kind: "def_init_function";
        id: number;
        args: ASTArgument[];
        statements: ASTStatement[];
        ref: ASTRef;
    };
    
    //
    // Statements
    //
    
    type ASTStatementLet = {
        kind: "statement_let";
        id: number;
        name: string;
        type: ASTTypeRef;
        expression: ASTExpression;
        ref: ASTRef;
    };
    
    type ASTStatementReturn = {
        kind: "statement_return";
        id: number;
        expression: ASTExpression | null;
        ref: ASTRef;
    };
    
    type ASTStatementExpression = {
        kind: "statement_expression";
        id: number;
        expression: ASTExpression;
        ref: ASTRef;
    };
    
    type ASTSTatementAssign = {
        kind: "statement_assign";
        id: number;
        path: ASTLvalueRef[];
        expression: ASTExpression;
        ref: ASTRef;
    };
    
    type ASTSTatementAugmentedAssign = {
        kind: "statement_augmentedassign";
        id: number;
        op: "+" | "-" | "*" | "/" | "%";
        path: ASTLvalueRef[];
        expression: ASTExpression;
        ref: ASTRef;
    };
    
    type ASTCondition = {
        kind: "statement_condition";
        id: number;
        expression: ASTExpression;
        trueStatements: ASTStatement[];
        falseStatements: ASTStatement[] | null;
        elseif: ASTCondition | null;
        ref: ASTRef;
    };
    
    type ASTStatementWhile = {
        kind: "statement_while";
        id: number;
        condition: ASTExpression;
        statements: ASTStatement[];
        ref: ASTRef;
    };
    
    type ASTStatementUntil = {
        kind: "statement_until";
        id: number;
        condition: ASTExpression;
        statements: ASTStatement[];
        ref: ASTRef;
    };
    
    type ASTStatementRepeat = {
        kind: "statement_repeat";
        id: number;
        iterations: ASTExpression;
        statements: ASTStatement[];
        ref: ASTRef;
    };
    
    type ASTStatementTry = {
        kind: "statement_try";
        id: number;
        statements: ASTStatement[];
        ref: ASTRef;
    };
    
    type ASTStatementTryCatch = {
        kind: "statement_try_catch";
        id: number;
        statements: ASTStatement[];
        catchName: string;
        catchStatements: ASTStatement[];
        ref: ASTRef;
    };
    
    //
    // Unions
    //
    
    type ASTStatement =
        | ASTStatementLet
        | ASTStatementReturn
        | ASTStatementExpression
        | ASTSTatementAssign
        | ASTSTatementAugmentedAssign
        | ASTCondition
        | ASTStatementWhile
        | ASTStatementUntil
        | ASTStatementRepeat
        | ASTStatementTry
        | ASTStatementTryCatch;

    type ASTNode =
        | ASTExpression
        | ASTStruct
        | ASTField
        | ASTContract
        | ASTArgument
        | ASTFunction
        | ASTOpCall
        | ASTStatementLet
        | ASTStatementReturn
        | ASTProgram
        | ASTPrimitive
        | ASTOpCallStatic
        | ASTStatementExpression
        | ASTNativeFunction
        | ASTSTatementAssign
        | ASTSTatementAugmentedAssign
        | ASTOpNew
        | ASTNewParameter
        | ASTTypeRef
        | ASTNull
        | ASTCondition
        | ASTInitFunction
        | ASTStatementWhile
        | ASTStatementUntil
        | ASTStatementRepeat
        | ASTStatementTry
        | ASTStatementTryCatch
        | ASTReceive
        | ASTLvalueRef
        | ASTString
        | ASTTrait
        | ASTProgramImport
        | ASTInitOf
        | ASTConstant;

    type ASTExpression =
        | ASTOpBinary
        | ASTOpUnary
        | ASTOpField
        | ASTNumber
        | ASTID
        | ASTBoolean
        | ASTOpCall
        | ASTOpCallStatic
        | ASTOpNew
        | ASTNull
        | ASTLvalueRef
        | ASTInitOf
        | ASTString
        | ASTConditional;
    type ASTType = ASTPrimitive | ASTStruct | ASTContract | ASTTrait;
    
    type DistributiveOmit<T, K extends keyof any> = T extends any
        ? Omit<T, K>
        : never;
}

declare module '*.ohm' {
    const content: string;
    export default content;
}
