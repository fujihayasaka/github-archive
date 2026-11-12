import { TreeViewSubTreeNodeElement } from './tree_view_sub_tree_node_element';
import type { TreeViewNodeType, TreeViewCheckedValue, TreeViewNodeInfo } from '../../shared_events';
export declare class TreeViewElement extends HTMLElement {
    #private;
    formInputContainer: HTMLElement;
    formInputPrototype: HTMLInputElement;
    connectedCallback(): void;
    disconnectedCallback(): void;
    handleEvent(event: Event): void;
    getFormInputValueForNode(node: Element): string | null;
    getNodePath(node: Element): string[];
    getNodeType(node: Element): TreeViewNodeType | null;
    markCurrentAtPath(path: string[]): void;
    get currentNode(): HTMLLIElement | null;
    expandAtPath(path: string[]): void;
    collapseAtPath(path: string[]): void;
    toggleAtPath(path: string[]): void;
    checkAtPath(path: string[]): void;
    uncheckAtPath(path: string[]): void;
    toggleCheckedAtPath(path: string[]): void;
    checkedValueAtPath(path: string[]): TreeViewCheckedValue;
    disabledValueAtPath(path: string[]): boolean;
    nodeAtPath(path: string[], selector?: string): Element | null;
    subTreeAtPath(path: string[]): TreeViewSubTreeNodeElement | null;
    leafAtPath(path: string[]): HTMLLIElement | null;
    setNodeCheckedValue(node: Element, value: TreeViewCheckedValue): void;
    getNodeCheckedValue(node: Element): TreeViewCheckedValue;
    getNodeDisabledValue(node: Element): boolean;
    setNodeDisabledValue(node: Element, disabled: boolean): void;
    nodeHasCheckBox(node: Element): boolean;
    nodeHasNativeAction(node: Element): boolean;
    expandAncestorsForNode(node: HTMLElement): void;
    infoFromNode(node: Element, newCheckedValue?: TreeViewCheckedValue): TreeViewNodeInfo | null;
}
declare global {
    interface Window {
        TreeViewElement: typeof TreeViewElement;
    }
}
