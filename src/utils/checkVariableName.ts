import { throwError } from "./ast";
import { ASTRef } from "./astRef";

export function checkVariableName(name: string, ref: ASTRef) {
    if (name.startsWith("__gen")) {
        throwError(`Variable name cannot start with "__gen"`, ref);
    }
    if (name.startsWith("__tact")) {
        throwError(`Variable name cannot start with "__tact"`, ref);
    }
}
