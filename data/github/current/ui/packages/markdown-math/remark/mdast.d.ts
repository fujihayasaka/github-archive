import type {Literal} from 'mdast'

export interface DisplayMathNode extends Literal {
  type: 'displaymath'
}

export interface InlineMathNode extends Literal {
  type: 'inlinemath'
}

declare module 'mdast' {
  interface BlockContentMap {
    displaymath: DisplayMathNode
  }

  interface PhrasingContentMap {
    displaymath: DisplayMathNode
    inlinemath: InlineMathNode
  }
}
