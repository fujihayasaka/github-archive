export declare class TreeViewIconPairElement extends HTMLElement {
    #private;
    expandedIcon: HTMLElement;
    collapsedIcon: HTMLElement;
    expanded: boolean;
    connectedCallback(): void;
    showExpanded(): void;
    showCollapsed(): void;
    toggle(): void;
}
declare global {
    interface Window {
        TreeViewIconPairElement: typeof TreeViewIconPairElement;
    }
}
