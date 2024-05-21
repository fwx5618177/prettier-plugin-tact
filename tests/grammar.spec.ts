import { expect, use } from 'chai';
import chaiJestSnapshot from 'chai-jest-snapshot';
import { describe, it, before } from 'mocha';

import { parse } from "../src/grammar/grammar";
import {  __DANGER_resetNodeId } from "../src/grammar/ast";
import { loadCases } from "../src/utils/loadCases";

use(chaiJestSnapshot);

describe("grammar", () => {

    before(function() {
        chaiJestSnapshot.resetSnapshotRegistry();
        // 设置全局快照文件名
        chaiJestSnapshot.setFilename(__dirname + "/__snapshots__/grammar-test.snap");
        chaiJestSnapshot.configureUsingMochaContext(this);
        __DANGER_resetNodeId();
    });

    it("should parse a simple function", function() {

        for (const r of loadCases(__dirname + "/test/")) {
            it("should parse " + r.name, function() {
                const result = parse(r.code, "<unknown>", "user");
                expect(result).to.matchSnapshot();
            });
        }
    });


    for (const r of loadCases(__dirname + "/test-failed/")) {
        it("should fail " + r.name, function() {
            expect(() => parse(r.code, "<unknown>", "user")).to.throw();
        });
    }
});