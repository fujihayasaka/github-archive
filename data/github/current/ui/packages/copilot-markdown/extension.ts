import type {Config, HookEvent, SanitizeAttributeHookEvent} from 'dompurify'
import type {MarkedExtension} from 'marked'

export type ReactBlockAttributes = Partial<Record<string, string>> & {children: string}

export interface ReactBlockExtension {
  /**
   * Selector that matches rendered target elements for this block. Typically a simple attribute selector matching
   * the corresponding `data-` attributes for this block, like `"[data-block-property-a][data-block-property-b]"`.
   */
  selector: string
  /**
   * Component to render. All attributes on the target element will be passed to the component as string values.
   * Contents of the element will be passed as `children`.
   */
  Component: React.FC<ReactBlockAttributes>
}

export type SanitizeAttributeHook = (currentNode: Element, data: SanitizeAttributeHookEvent, config: Config) => void

/** @deprecated */
export type AfterSanitizeAttributeHook = (currentNode: Element, data: HookEvent, config: Config) => void

export interface SanitizerExtension {
  allowedTagNames?: string[]
  /** List of class names to allow. Often this is `Object.values(styles)` to allow all classes from a CSS Module. */
  allowedClassNames?: Array<string | RegExp>
  /** Use to allow certain attributes through. If an attribute should be kept, set `data.forceKeepAttr` to `true`. */
  attributeHook?: SanitizeAttributeHook
  /**
   * @deprecated Avoid. To determine if an attribute should be kept, use `attributeHook`. To manipulate the DOM,
   * use a `marked` extension.
   */
  afterAttributesHook?: AfterSanitizeAttributeHook
}

/**
 * Extensions are defined as three separate items that each cover a step in the process. This unified object provides
 * all related code in one place.
 */
export interface CopilotMarkdownExtension {
  /** Parser/tokenizer extension for Marked. This controls how Markdown is parsed and turned into HTML. */
  marked?: MarkedExtension[]
  /**
   * Sanitizer configuration to allow the results of the `marked` step through the sanitizer. This should allow all
   * related attributes, class names, and tag names.
   */
  sanitizer?: SanitizerExtension
  /**
   * For richer content, we can hydrate the bare HTML element into a React block with a React extension. If hydrating
   * with React, properties can be passed through `data-` attributes.
   */
  react?: ReactBlockExtension
}
