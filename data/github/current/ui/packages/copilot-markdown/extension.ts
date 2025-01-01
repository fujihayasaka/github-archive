import type {ComponentProps, ElementType, ReactNode} from 'react'
import type {ExtraProps} from 'react-markdown'

import type {Transformer} from 'unified'

import type {Root as MarkdownRoot} from 'mdast'

import type {Root as HtmlRoot} from 'hast'

export const renderFallthrough = Symbol('renderFallthrough')

export type ElementName = Extract<ElementType, string>
type MarkdownComponentProps<Key extends ElementName> = ComponentProps<Key> & ExtraProps

export type DataProps = Partial<Record<`data-${string}`, string>>

export type ReactMarkdownComponents = {
  [Key in ElementName]?: (props: MarkdownComponentProps<Key>) => ReactNode
}

export type ReactComponentsExtensionRenderer<Key extends ElementName> = (
  props: MarkdownComponentProps<Key> & DataProps,
  // For convenience we provide the symbol here so you don't have to import it
  renderFallthroughSymbol: typeof renderFallthrough,
) => ReactNode | typeof renderFallthrough

export type ReactComponentsExtensionEntry<Key extends ElementName> = [Key, ReactComponentsExtensionRenderer<Key>]

export type ReactComponentsExtension = {
  [Key in ElementName]?: ReactComponentsExtensionRenderer<Key>
}
export const ReactComponentsExtension = {
  // Mapped types are great for objects where TS can easily understand that the key will correspond with the vaue,
  // but they fail when you need to iterate through the entries of that object. Inside each array entry the mapping
  // between key and value is lost - each entry would resolve to ReactComponentsExtensionEntry<ElementName>, which when
  // unpacked gives you the key type `ElementName` and value type `ReactComponentsExtensionRenderer<ElementName>`.
  // So we lie and act like there's only one entry in order to assert that the key and value are always related.
  entries: (extension: ReactComponentsExtension) =>
    Object.entries(extension) as Array<ReactComponentsExtensionEntry<'div'>>,
}

export type RemarkMarkdownTransformer = Transformer<MarkdownRoot, MarkdownRoot>
export type RehypeHtmlTransformer = Transformer<HtmlRoot, HtmlRoot>

/**
 * Extensions are defined as three separate items that each cover a step in the process. This unified object provides
 * all related code in one place.
 */
export interface CopilotMarkdownExtension {
  /**
   * Modify the raw markdown text before it's processed.
   * Note: Avoid using this for complex transformations - prefer working with the AST instead.
   */
  preprocessMarkdown?: (markdown: string) => string
  /**
   * Markdown syntax tree (mdast) transformer function to be run by Remark. Accepts the entire Markdown AST as input
   * and either mutates the input tree or returns the modified tree.
   *
   * The most common utility you will use for working with this AST is `unist-util-visit`, which provides a convenient
   * way to visit every node / 'walk the tree'.
   *
   * After this, the Markdown tree will be converted to the HTML tree using `mdast-util-to-hast`. Thus you can use
   * this transformer to customize how the Markdown is converted into HTML by adding special `hName`,
   * `hProperties`, and `hChildren` fields to the node's `data` object. For details, see
   * https://github.com/syntax-tree/mdast-util-to-hast?tab=readme-ov-file#fields-on-nodes. Note that when you set
   * property names, you must use the name format described in https://github.com/syntax-tree/hast?tab=readme-ov-file#propertyname.
   * `dataAttrToPropName` in `utils` will make this translation for you.
   */
  transformMarkdown?: RemarkMarkdownTransformer
  /**
   * HTML syntax tree (hast) transformer function to be run by Rehype. Accepts the entire Markdown AST as input
   * and either mutates the input tree or returns the modified tree.
   *
   * The most common utility you will use for working with this AST is `unist-util-visit`, which provides a convenient
   * way to visit every node / 'walk the tree'.
   */
  transformHtml?: RehypeHtmlTransformer
  /**
   * React component renderers for HTML elements. To fall through / skip the element, return the
   * `renderFallthrough` symbol. This would allow other plugins to catch this element and try their own rendering.
   * Typically, we will pass property objects via JSON and then decode them from the props with `parseJsonAttribute`
   * from `utils`.
   * @warning VERY IMPORTANT! This field must be a stable reference, and extensions that define this field may not be
   * added, removed, or reordered for the lifetime of the `MarkdownRenderer` component. If the set of `reactComponents`
   * objects changes after the initial render, an error will be thrown.
   * @example
   * reactComponents={{
   *   "code": (props, fallthrough) => {
   *     const codeBlockProps = parseJsonAttribute<CodeBlockProps>(props, "data-codeblock-props")
   *     return prcodeBlockProps ? <CodeBlock {...codeBlockProps} /> : fallthrough
   * }}
   */
  reactComponents?: ReactComponentsExtension
}
