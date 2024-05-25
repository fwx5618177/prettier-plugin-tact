// AUTOGENERATED FILE
// This file was generated from comment.ohm by `ohm generateBundles`.

import {
  BaseActionDict,
  Grammar,
  IterationNode,
  Node,
  NonterminalNode,
  Semantics,
  TerminalNode
} from 'ohm-js';

export interface CommentActionDict<T> extends BaseActionDict<T> {
  Program?: (this: NonterminalNode, arg0: IterationNode) => T;
  space?: (this: NonterminalNode, arg0: NonterminalNode | TerminalNode) => T;
  comment?: (this: NonterminalNode, arg0: NonterminalNode) => T;
  lineTerminator?: (this: NonterminalNode, arg0: TerminalNode) => T;
  multiLineComment?: (this: NonterminalNode, arg0: TerminalNode, arg1: IterationNode, arg2: TerminalNode) => T;
  singleLineComment?: (this: NonterminalNode, arg0: TerminalNode, arg1: IterationNode) => T;
}

export interface CommentSemantics extends Semantics {
  addOperation<T>(name: string, actionDict: CommentActionDict<T>): this;
  extendOperation<T>(name: string, actionDict: CommentActionDict<T>): this;
  addAttribute<T>(name: string, actionDict: CommentActionDict<T>): this;
  extendAttribute<T>(name: string, actionDict: CommentActionDict<T>): this;
}

export interface CommentGrammar extends Grammar {
  createSemantics(): CommentSemantics;
  extendSemantics(superSemantics: CommentSemantics): CommentSemantics;
}

declare const grammar: CommentGrammar;
export default grammar;

