import { TreeViewIconPairElement } from './tree_view_icon_pair_element';
import { TreeViewIncludeFragmentElement } from './tree_view_include_fragment_element';
import { TreeViewElement } from './tree_view';
type LoadingState = 'loading' | 'error' | 'success';
export type SelectStrategy = 'self' | 'descendants' | 'mixed_descendants';
export declare class TreeViewSubTreeNodeElement extends HTMLElement {
    #private;
    node: HTMLElement;
    subTree: HTMLElement;
    iconPair: TreeViewIconPairElement;
    toggleButton: HTMLElement;
    expandedToggleIcon: HTMLElement;
    collapsedToggleIcon: HTMLElement;
    includeFragment: TreeViewIncludeFragmentElement;
    loadingIndicator: HTMLElement;
    loadingFailureMessage: HTMLElement;
    retryButton: HTMLButtonElement;
    connectedCallback(): void;
    get expanded(): boolean;
    set expanded(newValue: boolean);
    get loadingState(): LoadingState;
    set loadingState(newState: LoadingState);
    get selectStrategy(): SelectStrategy;
    disconnectedCallback(): void;
    handleEvent(event: Event): void;
    expand(): void;
    collapse(): void;
    toggle(): void;
    get nodes(): NodeListOf<Element>;
    eachDirectDescendantNode(): Generator<Element>;
    eachDescendantNode(): Generator<Element>;
    eachAncestorSubTreeNode(): Generator<TreeViewSubTreeNodeElement>;
    get isEmpty(): boolean;
    get treeView(): TreeViewElement | null;
    toggleChecked(): void;
}
declare global {
    interface Window {
        TreeViewSubTreeNodeElement: typeof TreeViewSubTreeNodeElement;
    }
}
export {};
