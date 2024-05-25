import {
    ASTNode,
    ASTProgram,
    ASTStruct,
    ASTContract,
    ASTField,
    ASTFunction,
    ASTConstant,
    ASTTypeRef,
    ASTExpression,
    ASTStatement,
} from './grammars/ast';

// Utility function to indent lines
function indent(code: string, level: number = 1): string {
    const indentation = '  '.repeat(level);
    return code
        .split('\n')
        .map(line => indentation + line)
        .join('\n');
}

export function printTact(node: ASTNode, level: number = 0): string {
    let output = '';

    switch (node.kind) {
        case 'program':
            (node as ASTProgram).entries.forEach(entry => {
                output += printTact(entry) + '\n';
            });
            break;

        case 'def_struct':
            const structNode = node as ASTStruct;
            output += `struct ${structNode.name} {\n`;
            structNode.fields.forEach(field => {
                output += indent(printTact(field), level + 1) + '\n';
            });
            output += '}\n';
            break;

        case 'def_contract':
            const contractNode = node as ASTContract;
            output += `contract ${contractNode.name} {\n`;
            contractNode.declarations.forEach(declaration => {
                output += indent(printTact(declaration), level + 1) + '\n';
            });
            output += '}\n';
            break;

        case 'def_field':
            const fieldNode = node as ASTField;
            output += `${fieldNode.name}: ${printType(fieldNode.type)}`;
            if (fieldNode.init) {
                output += ` = ${printTact(fieldNode.init)}`;
            }
            output += ';';
            break;

        case 'def_function':
            const functionNode = node as ASTFunction;
            const functionAttrs = functionNode.attributes.map(attr => attr.type).join(' ');
            output += `${functionAttrs} fun ${functionNode.name}(${functionNode.args.map(arg => printTact(arg)).join(', ')})`;
            if (functionNode.return) {
                output += `: ${printType(functionNode.return)}`;
            }
            output += ` {\n`;
            if (functionNode.statements) {
                functionNode.statements.forEach(statement => {
                    output += indent(printTact(statement), level + 1) + '\n';
                });
            }
            output += '}\n';
            break;

        case 'def_constant':
            const constantNode = node as ASTConstant;
            const constantAttrs = constantNode.attributes.map(attr => attr.type).join(' ');
            output += `${constantAttrs} const ${constantNode.name}: ${printType(constantNode.type)}`;
            if (constantNode.value) {
                output += ` = ${printTact(constantNode.value)}`;
            }
            output += ';';
            break;

        case 'def_argument':
            const argNode = node;
            output += `${argNode.name}: ${printType(argNode.type)}`;
            break;

        case 'number':
        case 'boolean':
        case 'string':
        case 'id':
        case 'null':
            output += printLiteral(node);
            break;

        case 'op_binary':
        case 'op_unary':
        case 'op_field':
        case 'op_call':
        case 'op_static_call':
        case 'op_new':
        case 'conditional':
            output += printExpression(node as ASTExpression);
            break;

        case 'statement_let':
        case 'statement_return':
        case 'statement_expression':
        case 'statement_assign':
        case 'statement_augmentedassign':
        case 'statement_condition':
        case 'statement_while':
        case 'statement_until':
        case 'statement_repeat':
        case 'statement_try':
        case 'statement_try_catch':
        case 'statement_foreach':
            output += printStatement(node as ASTStatement);
            break;

        default:
            throw new Error(`Unsupported AST node kind: ${(node as ASTNode).kind}`);
    }

    return output.trim();
}

// Utility function to print type references
function printType(type: ASTTypeRef): string {
    switch (type.kind) {
        case 'type_ref_simple':
            return `${type.name}${type.optional ? '?' : ''}`;
        case 'type_ref_map':
            return `map<${type.key}${type.keyAs ? ` as ${type.keyAs}` : ''}, ${type.value}${type.valueAs ? ` as ${type.valueAs}` : ''}>`;
        case 'type_ref_bounced':
            return `bounced<${type.name}>`;
        default:
            throw new Error(`Unsupported type reference kind: ${(type as ASTTypeRef).kind}`);
    }
}

// Utility function to print literals
function printLiteral(node: ASTNode): string {
    switch (node.kind) {
        case 'number':
            return (node as any).value.toString();
        case 'boolean':
            return (node as any).value.toString();
        case 'string':
            return `"${(node as any).value}"`;
        case 'id':
            return (node as any).value;
        case 'null':
            return 'null';
        default:
            throw new Error(`Unsupported literal kind: ${(node as ASTNode).kind}`);
    }
}

// Utility function to print expressions
function printExpression(node: ASTExpression): string {
    switch (node.kind) {
        case 'op_binary':
            return `${printTact(node.left)} ${node.op} ${printTact(node.right)}`;
        case 'op_unary':
            return `${node.op}${printTact(node.right)}`;
        case 'op_field':
            return `${printTact(node.src)}.${node.name}`;
        case 'op_call':
            return `${printTact(node.src)}.${node.name}(${node.args.map(arg => printTact(arg)).join(', ')})`;
        case 'op_static_call':
            return `${node.name}(${node.args.map(arg => printTact(arg)).join(', ')})`;
        case 'op_new':
            return `new ${node.type}(${node.args.map(arg => printTact(arg)).join(', ')})`;
        case 'conditional':
            return `${printTact(node.condition)} ? ${printTact(node.thenBranch)} : ${printTact(node.elseBranch)}`;
        default:
            throw new Error(`Unsupported expression kind: ${(node as ASTExpression).kind}`);
    }
}

// Utility function to print statements
function printStatement(node: ASTStatement): string {
    switch (node.kind) {
        case 'statement_let':
            return `let ${node.name}: ${printType(node.type)} = ${printTact(node.expression)};`;
        case 'statement_return':
            return `return${node.expression ? ` ${printTact(node.expression)}` : ''};`;
        case 'statement_expression':
            return `${printTact(node.expression)};`;
        case 'statement_assign':
            return `${printTact(node.path[0])} = ${printTact(node.expression)};`;
        case 'statement_augmentedassign':
            return `${printTact(node.path[0])} ${node.op}= ${printTact(node.expression)};`;
        case 'statement_condition':
            let result = `if (${printTact(node.expression)}) {\n`;
            result += node.trueStatements.map(stmt => indent(printTact(stmt))).join('\n') + '\n';
            if (node.falseStatements) {
                result += `} else {\n`;
                result +=
                    node.falseStatements.map(stmt => indent(printTact(stmt))).join('\n') + '\n';
            }
            if (node.elseif) {
                result += `} else ${printTact(node.elseif)}\n`;
            }
            result += `}`;
            return result;
        case 'statement_while':
            return `while (${printTact(node.condition)}) {\n${node.statements.map(stmt => indent(printTact(stmt))).join('\n')}\n}`;
        case 'statement_until':
            return `do {\n${node.statements.map(stmt => indent(printTact(stmt))).join('\n')}\n} until (${printTact(node.condition)});`;
        case 'statement_repeat':
            return `repeat (${printTact(node.iterations)}) {\n${node.statements.map(stmt => indent(printTact(stmt))).join('\n')}\n}`;
        case 'statement_try':
            return `try {\n${node.statements.map(stmt => indent(printTact(stmt))).join('\n')}\n}`;
        case 'statement_try_catch':
            return `try {\n${node.statements.map(stmt => indent(printTact(stmt))).join('\n')}\n} catch (${node.catchName}) {\n${node.catchStatements.map(stmt => indent(printTact(stmt))).join('\n')}\n}`;
        case 'statement_foreach':
            return `foreach (${node.keyName}, ${node.valueName} in ${printTact(node.map)}) {\n${node.statements.map(stmt => indent(printTact(stmt))).join('\n')}\n}`;
        default:
            throw new Error(`Unsupported statement kind: ${(node as ASTStatement).kind}`);
    }
}
