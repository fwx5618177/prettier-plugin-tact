import { expect } from 'chai';
import { describe, it } from 'mocha';
import { ASTRef, traverse } from '../src/grammar/ast';
import { Interval as RawInterval } from 'ohm-js';
import { loadCases } from '../src/utils/loadCases';
import { parse, parseImports } from '../src/grammar/grammar';

describe('ASTRef', function () {
    describe('AST read', function () {
        for (const r of loadCases(__dirname + '/single/')) {
            it('should parse ' + r.name, function () {
                const importList = parseImports(r.code, '<unknown>', 'user');
                expect(importList.length).not.equal(0);
                expect(importList).to.be.an('array');

                // TODO: to complete the test
                const code = parse(r.code, '<unknown>', 'user');
                traverse(code, console.log);
            });
        }
    });
});
