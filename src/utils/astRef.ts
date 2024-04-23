import { Interval as RawInterval } from "ohm-js";

export class ASTRef {
    readonly #interval: RawInterval;
    readonly #file: string | null;

    static merge(...refs: ASTRef[]) {
        if (refs.length === 0) {
            throw Error("Cannot merge 0 refs");
        }

        let r = refs[0]!.#interval;
        const file = refs[0]!.#file;
        for (let i = 1; i < refs.length; i++) {
            r = r.coverageWith(r, refs[i]!.#interval);
        }
        return new ASTRef(r, file);
    }

    constructor(interval: RawInterval, file: string | null) {
        this.#interval = interval;
        this.#file = file;
    }

    get file() {
        return this.#file;
    }

    get contents() {
        return this.#interval.contents;
    }

    get interval() {
        return this.#interval;
    }
}
