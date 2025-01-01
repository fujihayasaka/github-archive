var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __classPrivateFieldGet = (this && this.__classPrivateFieldGet) || function (receiver, state, kind, f) {
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a getter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot read private member from an object whose class did not declare it");
    return kind === "m" ? f : kind === "a" ? f.call(receiver) : f ? f.value : state.get(receiver);
};
var _TreeViewIconPairElement_instances, _TreeViewIconPairElement_update;
import { controller, target } from '@github/catalyst';
import { observeMutationsUntilConditionMet } from '../../utils';
let TreeViewIconPairElement = class TreeViewIconPairElement extends HTMLElement {
    constructor() {
        super(...arguments);
        _TreeViewIconPairElement_instances.add(this);
    }
    connectedCallback() {
        observeMutationsUntilConditionMet(this, () => Boolean(this.collapsedIcon) && Boolean(this.expandedIcon), () => {
            this.expanded = this.collapsedIcon.hidden;
        });
    }
    showExpanded() {
        this.expanded = true;
        __classPrivateFieldGet(this, _TreeViewIconPairElement_instances, "m", _TreeViewIconPairElement_update).call(this);
    }
    showCollapsed() {
        this.expanded = false;
        __classPrivateFieldGet(this, _TreeViewIconPairElement_instances, "m", _TreeViewIconPairElement_update).call(this);
    }
    toggle() {
        this.expanded = !this.expanded;
        __classPrivateFieldGet(this, _TreeViewIconPairElement_instances, "m", _TreeViewIconPairElement_update).call(this);
    }
};
_TreeViewIconPairElement_instances = new WeakSet();
_TreeViewIconPairElement_update = function _TreeViewIconPairElement_update() {
    if (this.expanded) {
        this.expandedIcon.hidden = false;
        this.collapsedIcon.hidden = true;
    }
    else {
        this.expandedIcon.hidden = true;
        this.collapsedIcon.hidden = false;
    }
};
__decorate([
    target
], TreeViewIconPairElement.prototype, "expandedIcon", void 0);
__decorate([
    target
], TreeViewIconPairElement.prototype, "collapsedIcon", void 0);
TreeViewIconPairElement = __decorate([
    controller
], TreeViewIconPairElement);
export { TreeViewIconPairElement };
if (!window.customElements.get('tree-view-icon-pair')) {
    window.TreeViewIconPairElement = TreeViewIconPairElement;
    window.customElements.define('tree-view-icon-pair', TreeViewIconPairElement);
}
