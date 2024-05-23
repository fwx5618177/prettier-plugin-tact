import { expect } from 'chai';
import { describe, it } from 'mocha';
import { ASTRef, traverse } from '../src/grammar/ast';
import { Interval as RawInterval } from 'ohm-js';
import { loadCases } from '../src/utils/loadCases';
import { parse, parseComments, parseImports } from '../src/grammar/grammar';

describe('ASTRef', function () {
    describe('AST read', function () {
        for (const r of loadCases(__dirname + '/single/')) {
            it('should parse ' + r.name, function () {
                const importList = parseImports(r.code, '<unknown>', 'user');
                expect(importList.length).not.equal(0);
                expect(importList).to.be.an('array');

                const commentList = parseComments(r.code, '<unknown>', 'user');
                console.log(commentList);

                // TODO: to complete the test
                // const code = parse(r.code, '<unknown>', 'user');
                // traverse(code, node => {
                //     if (node.kind === 'comment') {
                //         console.log(node);
                //     }
                // });
            });
        }

        it('should include comments in the AST', function () {
            const code = `
// This is a single line comment
/* This is a
    multi-line comment */
    fun testFunc(a: Int): Int {
        const b: Int = a == 123 ? 1 : 2;
        return b;
    }
`;
            const ast = parse(code, '<test>', 'user');

            let foundSingleLineComment = false;
            let foundMultiLineComment = false;

            traverse(ast, node => {
                if (node.kind === 'comment') {
                    if (node.value.includes('single line comment')) {
                        foundSingleLineComment = true;
                    }
                    if (node.value.includes('multi-line comment')) {
                        foundMultiLineComment = true;
                    }
                }
            });

            expect(foundSingleLineComment).to.be.true;
            expect(foundMultiLineComment).to.be.true;
        });
    });
});
