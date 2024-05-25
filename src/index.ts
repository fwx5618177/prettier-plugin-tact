import { SupportLanguage, Parser, Printer } from 'prettier';

import { parse } from './grammars/grammar';
import { ASTNode } from './grammars/ast';
import { printTact } from './printer';

type TactASTNode = ASTNode & {
    start: number;
    end: number;
};

const languages: SupportLanguage[] = [
    {
        name: 'Tact',
        parsers: ['tact'],
        extensions: ['.tact'],
    },
];

const parsers: Record<'tact', Parser> = {
    tact: {
        parse: (text: string) => parse(text, '<unknown>', 'user'),
        astFormat: 'tact-ast',
        locStart: (node: TactASTNode) => node.start,
        locEnd: (node: TactASTNode) => node.end,
    },
};

const printers: Record<'tact-ast', Printer> = {
    'tact-ast': {
        print: (path, _options, _print): string => {
            return printTact(path.getValue());
        },
    },
};

export default {
    languages,
    parsers,
    printers,
};
