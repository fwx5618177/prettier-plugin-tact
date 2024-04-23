import { ASTRef } from "../utils/astRef";

import { TactSourceError } from "./TactSourceError";


export class TactSyntaxError extends TactSourceError {
    constructor(message: string, ref: ASTRef) {
        super(message, ref);
    }
}