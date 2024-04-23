import { Node as RawNode } from "ohm-js";
import { DistributiveOmit, ASTNode } from "tact-format";

import { TactSyntaxError } from "../errors/TactSyntaxError";

import { ASTRef } from "./astRef";


let nextId = 1;

export function createNode(src: DistributiveOmit<ASTNode, "id">): ASTNode {
    return Object.freeze(Object.assign({ id: nextId++ }, src));
}
export function cloneASTNode<T extends ASTNode>(src: T): T {
    return { ...src, id: nextId++ };
}

export function __DANGER_resetNodeId() {
    nextId = 1;
}

let currentFile: string | null = null;

export function inFile<T>(path: string, callback: () => T) {
    currentFile = path;
    const r = callback();
    currentFile = null;
    return r;
}

export function createRef(s: RawNode, ...extra: RawNode[]): ASTRef {
    let i = s.source;

    if (extra.length > 0) {
        i = i.coverageWith(...extra.map((e) => e.source));
    }
    return new ASTRef(i, currentFile);
}

export function throwError(message: string, ref: ASTRef): never {
    if (ref.file) {
        const lc = ref.interval.getLineAndColumn() as {
            lineNum: number;
            colNum: number;
        };
        throw new TactSyntaxError(
            ref.file +
                ":" +
                lc.lineNum +
                ":" +
                lc.colNum +
                ": " +
                message +
                "\n" +
                ref.interval.getLineAndColumnMessage(),
            ref,
        );
    } else {
        throw new TactSyntaxError(
            message + ref.interval.getLineAndColumnMessage(),
            ref,
        );
    }
}

export function traverse(node: ASTNode, callback: (node: ASTNode) => void) {
    callback(node);

    //
    // Program
    //

    if (node.kind === "program") {
        for (const e of node.entries) {
            traverse(e, callback);
        }
    }
    if (node.kind === "def_contract") {
        for (const e of node.declarations) {
            traverse(e, callback);
        }
    }
    if (node.kind === "def_struct") {
        for (const e of node.fields) {
            traverse(e, callback);
        }
    }
    if (node.kind === "def_trait") {
        for (const e of node.declarations) {
            traverse(e, callback);
        }
    }

    //
    // Functions
    //

    if (node.kind === "def_function") {
        for (const e of node.args) {
            traverse(e, callback);
        }
        if (node.statements) {
            for (const e of node.statements) {
                traverse(e, callback);
            }
        }
    }
    if (node.kind === "def_init_function") {
        for (const e of node.args) {
            traverse(e, callback);
        }
        for (const e of node.statements) {
            traverse(e, callback);
        }
    }
    if (node.kind === "def_receive") {
        for (const e of node.statements) {
            traverse(e, callback);
        }
    }
    if (node.kind === "def_native_function") {
        for (const e of node.args) {
            traverse(e, callback);
        }
    }
    if (node.kind === "def_field") {
        if (node.init) {
            traverse(node.init, callback);
        }
    }
    if (node.kind === "def_constant") {
        if (node.value) {
            traverse(node.value, callback);
        }
    }

    //
    // Statements
    //

    if (node.kind === "statement_let") {
        traverse(node.type, callback);
        traverse(node.expression, callback);
    }
    if (node.kind === "statement_return") {
        if (node.expression) {
            traverse(node.expression, callback);
        }
    }
    if (node.kind === "statement_expression") {
        traverse(node.expression, callback);
    }
    if (node.kind === "statement_assign") {
        for (const e of node.path) {
            traverse(e, callback);
        }
        traverse(node.expression, callback);
    }
    if (node.kind === "statement_augmentedassign") {
        for (const e of node.path) {
            traverse(e, callback);
        }
        traverse(node.expression, callback);
    }
    if (node.kind === "statement_condition") {
        traverse(node.expression, callback);
        for (const e of node.trueStatements) {
            traverse(e, callback);
        }
        if (node.falseStatements) {
            for (const e of node.falseStatements) {
                traverse(e, callback);
            }
        }
        if (node.elseif) {
            traverse(node.elseif, callback);
        }
    }
    if (node.kind === "statement_while") {
        traverse(node.condition, callback);
        for (const e of node.statements) {
            traverse(e, callback);
        }
    }
    if (node.kind === "statement_until") {
        traverse(node.condition, callback);
        for (const e of node.statements) {
            traverse(e, callback);
        }
    }
    if (node.kind === "statement_repeat") {
        traverse(node.iterations, callback);
        for (const e of node.statements) {
            traverse(e, callback);
        }
    }
    if (node.kind === "statement_try") {
        for (const e of node.statements) {
            traverse(e, callback);
        }
    }
    if (node.kind === "statement_try_catch") {
        for (const e of node.statements) {
            traverse(e, callback);
        }
        for (const e of node.catchStatements) {
            traverse(e, callback);
        }
    }
    if (node.kind === "op_binary") {
        traverse(node.left, callback);
        traverse(node.right, callback);
    }
    if (node.kind === "op_unary") {
        traverse(node.right, callback);
    }
    if (node.kind === "op_field") {
        traverse(node.src, callback);
    }
    if (node.kind === "op_call") {
        traverse(node.src, callback);
        for (const e of node.args) {
            traverse(e, callback);
        }
    }
    if (node.kind === "op_static_call") {
        for (const e of node.args) {
            traverse(e, callback);
        }
    }
    if (node.kind === "op_new") {
        for (const e of node.args) {
            traverse(e, callback);
        }
    }
    if (node.kind === "new_parameter") {
        traverse(node.exp, callback);
    }
    if (node.kind === "conditional") {
        traverse(node.condition, callback);
        traverse(node.thenBranch, callback);
        traverse(node.elseBranch, callback);
    }
}