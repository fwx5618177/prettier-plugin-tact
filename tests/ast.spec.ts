import { expect } from 'chai';
import { describe, it } from 'mocha';
import { ASTRef, traverse } from '../src/grammars/ast';
import { Interval as RawInterval } from 'ohm-js';
import { loadCases } from '../src/utils/loadCases';
import { parse, parseComments, parseImports } from '../src/grammars/grammar';
import rawGrammar from './test-schema/comment.ohm-bundle';

describe('ASTRef', function () {
    describe('AST read', function () {
        for (const r of loadCases(__dirname + '/single/')) {
            it('should parse ' + r.name, function () {
                const importList = parseImports(r.code, '<unknown>', 'user');
                expect(importList.length).not.equal(0);
                expect(importList).to.be.an('array');
                // const commentList = parseComments(r.code, '<unknown>', 'user');
                // console.log(commentList);
                // TODO: to complete the test
                const code = parse(r.code, '<unknown>', 'user');
                console.log(code);
                // traverse(code, node => {
                //     if (node.kind === 'comment') {
                //         console.log(node);
                //     }
                // });
            });
        }
        // it('should include comments in the AST', function () {
        //     const code = `
        //             /* This is a multi-line comment*/
        //             // This is a single line comment
        //             //! This is a single line important comment
        //             /// This is a single line doc comment
        //     fun testFunc(a: Int): Int {
        //         let b: Int = a == 123 ? 1 : 2;
        //         return b;
        //     }
        // `;
        //     const ast = parse(code, '<test>', 'user');
        //     console.log(ast);
        //     let foundSingleLineComment = false;
        //     let foundMultiLineComment = false;
        //     // traverse(ast, node => {
        //     //     if (node.kind === 'comment') {
        //     //         if (node.value.includes('single line comment')) {
        //     //             foundSingleLineComment = true;
        //     //         }
        //     //         if (node.value.includes('multi-line comment')) {
        //     //             foundMultiLineComment = true;
        //     //         }
        //     //     }
        //     // });
        //     expect(foundSingleLineComment).to.be.true;
        //     expect(foundMultiLineComment).to.be.true;
        // });
        // it('should generate comments from customized code', function () {
        //     const grammar = rawGrammar.createSemantics();
        //     const semantics = rawGrammar.createSemantics().addOperation('extractComment', {
        //         _terminal() {
        //             return this.sourceString;
        //         },
        //         comment(arg) {
        //             return arg.sourceString;
        //         },
        //         multiLineComment(_start, body, _end) {
        //             return body.sourceString;
        //         },
        //         singleLineComment(_start, body) {
        //             return body.sourceString;
        //         },
        //         Program(body) {
        //             return body.children
        //                 .map(c => c?.extractComment())
        //                 .filter(Boolean)
        //                 .join('\n');
        //         },
        //     });
        //     const matchResult = rawGrammar.match(
        //         `// This is a single line comment\n1211\nconst a = 1;`,
        //     );
        //     if (matchResult.failed()) {
        //         console.log('Error:', matchResult.message, matchResult.shortMessage);
        //     }
        //     const comment = semantics(matchResult).extractComment();
        //     console.log({
        //         comment,
        //     }); // 输出: "This is a single line comment"
        //     expect(comment).to.be.equal('This is a single line comment');
        // });
    });
});
