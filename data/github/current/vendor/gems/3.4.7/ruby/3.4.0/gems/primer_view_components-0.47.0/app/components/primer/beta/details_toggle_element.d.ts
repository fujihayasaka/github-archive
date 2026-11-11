/**
 * A companion Catalyst element for the Details view component. This element
 * ensures the <details> and <summary> elements markup is properly accessible by
 * updating the aria-label and aria-expanded attributes on click.
 *
 * aria-label values are only set if provided via the `data-aria-label-open` and
 * `data-aria-label-closed` attributes on the summary target. If these attributes
 * are not present, no aria-label will be set, allowing screen readers to use
 * the visible text content.
 *
 * @example
 * ```html
 * <details-toggle>
 *   <details open=true data-target="details-toggle.detailsTarget">
 *     <summary
 *       aria-expanded="true"
 *       aria-label="Collapse me"
 *       data-target="details-toggle.summaryTarget"
 *       data-action="click:details-toggle#toggle"
 *       data-aria-label-closed="Expand me"
 *       data-aria-label-open="Collapse me"
 *     >
 *       Click me
 *     </summary>
 *     <div>Contents</div>
 *   </details>
 * </details-toggle>
 * ```
 */
declare class DetailsToggleElement extends HTMLElement {
    detailsTarget: HTMLDetailsElement;
    summaryTarget: HTMLElement;
    toggle(): void;
}
declare global {
    interface Window {
        DetailsToggleElement: typeof DetailsToggleElement;
    }
}
export {};
