import {remark} from 'remark'
import {remarkMath} from '../remark-math'
import type {MarkdownMathOptions} from '../../options'

export const parse = (md: string, options?: MarkdownMathOptions) => remark().use(remarkMath, options).parse(md)
