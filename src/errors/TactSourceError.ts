import { ASTRef } from "../utils/astRef";

export class TactSourceError extends Error {
    readonly ref: ASTRef;
    constructor(message: string, ref: ASTRef) {
        super(message);
        this.ref = ref;
    }
}