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
var __classPrivateFieldSet = (this && this.__classPrivateFieldSet) || function (receiver, state, value, kind, f) {
    if (kind === "m") throw new TypeError("Private method is not writable");
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a setter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot write private member to an object whose class did not declare it");
    return (kind === "a" ? f.call(receiver, value) : f ? f.value = value : state.set(receiver, value)), value;
};
var _SelectPanelElement_instances, _SelectPanelElement_dialogIntersectionObserver, _SelectPanelElement_abortController, _SelectPanelElement_originalLabel, _SelectPanelElement_inputName, _SelectPanelElement_selectedItems, _SelectPanelElement_loadingDelayTimeoutId, _SelectPanelElement_loadingAnnouncementTimeoutId, _SelectPanelElement_hasLoadedData, _SelectPanelElement_softDisableItems, _SelectPanelElement_updateTabIndices, _SelectPanelElement_potentiallyDisallowActivation, _SelectPanelElement_isAnchorActivationViaSpace, _SelectPanelElement_isActivation, _SelectPanelElement_checkSelectedItems, _SelectPanelElement_addSelectedItem, _SelectPanelElement_removeSelectedItem, _SelectPanelElement_setTextFieldLoadingSpinnerTimer, _SelectPanelElement_handleIncludeFragmentEvent, _SelectPanelElement_toggleIncludeFragmentElements, _SelectPanelElement_handleRemoteInputEvent, _SelectPanelElement_defaultFilterFn, _SelectPanelElement_handleSearchFieldEvent, _SelectPanelElement_updateItemVisibility, _SelectPanelElement_inErrorState, _SelectPanelElement_setErrorState, _SelectPanelElement_clearErrorState, _SelectPanelElement_maybeAnnounce, _SelectPanelElement_fetchStrategy_get, _SelectPanelElement_filterInputTextFieldElement_get, _SelectPanelElement_performFilteringLocally, _SelectPanelElement_handleInvokerActivated, _SelectPanelElement_handleDialogItemActivated, _SelectPanelElement_handleItemActivated, _SelectPanelElement_setDynamicLabel, _SelectPanelElement_updateInput, _SelectPanelElement_firstItem_get, _SelectPanelElement_hideItem, _SelectPanelElement_showItem, _SelectPanelElement_getItemContent;
import { getAnchoredPosition } from '@primer/behaviors';
import { controller, target } from '@github/catalyst';
import { IncludeFragmentElement } from '@github/include-fragment-element';
import '@primer/live-region-element';
import '@oddbird/popover-polyfill';
import { observeMutationsUntilConditionMet } from '../utils';
const validSelectors = ['[role="option"]'];
const menuItemSelectors = validSelectors.join(',');
const visibleMenuItemSelectors = validSelectors.map(selector => `:not([hidden]) > ${selector}`).join(',');
var FetchStrategy;
(function (FetchStrategy) {
    FetchStrategy[FetchStrategy["REMOTE"] = 0] = "REMOTE";
    FetchStrategy[FetchStrategy["EVENTUALLY_LOCAL"] = 1] = "EVENTUALLY_LOCAL";
    FetchStrategy[FetchStrategy["LOCAL"] = 2] = "LOCAL";
})(FetchStrategy || (FetchStrategy = {}));
var ErrorStateType;
(function (ErrorStateType) {
    ErrorStateType[ErrorStateType["BODY"] = 0] = "BODY";
    ErrorStateType[ErrorStateType["BANNER"] = 1] = "BANNER";
})(ErrorStateType || (ErrorStateType = {}));
const updateWhenVisible = (() => {
    const anchors = new Set();
    let resizeObserver = null;
    function updateVisibleAnchors() {
        for (const anchor of anchors) {
            anchor.updateAnchorPosition();
        }
    }
    return (el) => {
        // eslint-disable-next-line github/prefer-observers
        window.addEventListener('resize', updateVisibleAnchors);
        // eslint-disable-next-line github/prefer-observers
        window.addEventListener('scroll', updateVisibleAnchors);
        resizeObserver || (resizeObserver = new ResizeObserver(() => {
            for (const anchor of anchors) {
                anchor.updateAnchorPosition();
            }
        }));
        resizeObserver.observe(el.ownerDocument.documentElement);
        el.addEventListener('dialog:close', () => {
            el.invokerElement?.setAttribute('aria-expanded', 'false');
            anchors.delete(el);
        });
        el.addEventListener('dialog:open', () => {
            anchors.add(el);
        });
    };
})();
let SelectPanelElement = class SelectPanelElement extends HTMLElement {
    constructor() {
        super(...arguments);
        _SelectPanelElement_instances.add(this);
        _SelectPanelElement_dialogIntersectionObserver.set(this, void 0);
        _SelectPanelElement_abortController.set(this, void 0);
        _SelectPanelElement_originalLabel.set(this, '');
        _SelectPanelElement_inputName.set(this, '');
        _SelectPanelElement_selectedItems.set(this, new Map());
        _SelectPanelElement_loadingDelayTimeoutId.set(this, null);
        _SelectPanelElement_loadingAnnouncementTimeoutId.set(this, null);
        _SelectPanelElement_hasLoadedData.set(this, false);
    }
    get open() {
        return this.dialog.open;
    }
    get selectVariant() {
        return this.getAttribute('data-select-variant');
    }
    get ariaSelectionType() {
        return this.selectVariant === 'multiple' ? 'aria-checked' : 'aria-selected';
    }
    set selectVariant(variant) {
        if (variant) {
            this.setAttribute('data-select-variant', variant);
        }
        else {
            this.removeAttribute('variant');
        }
    }
    get dynamicLabelPrefix() {
        const prefix = this.getAttribute('data-dynamic-label-prefix');
        if (!prefix)
            return '';
        return `${prefix}:`;
    }
    get dynamicAriaLabelPrefix() {
        const prefix = this.getAttribute('data-dynamic-aria-label-prefix');
        if (!prefix)
            return '';
        return `${prefix}:`;
    }
    set dynamicLabelPrefix(value) {
        this.setAttribute('data-dynamic-label', value);
    }
    get dynamicLabel() {
        return this.hasAttribute('data-dynamic-label');
    }
    set dynamicLabel(value) {
        this.toggleAttribute('data-dynamic-label', value);
    }
    get invokerElement() {
        const id = this.querySelector('dialog')?.id;
        if (!id)
            return null;
        for (const el of this.querySelectorAll(`[aria-controls]`)) {
            if (el.getAttribute('aria-controls') === id) {
                return el;
            }
        }
        return null;
    }
    get closeButton() {
        return this.querySelector('button[data-close-dialog-id]');
    }
    get invokerLabel() {
        if (!this.invokerElement)
            return null;
        return this.invokerElement.querySelector('.Button-label');
    }
    get selectedItems() {
        return Array.from(__classPrivateFieldGet(this, _SelectPanelElement_selectedItems, "f").values());
    }
    get align() {
        return (this.getAttribute('anchor-align') || 'start');
    }
    get side() {
        return (this.getAttribute('anchor-side') || 'outside-bottom');
    }
    updateAnchorPosition() {
        // If the selectPanel is removed from the screen on resize close the dialog
        if (this && this.offsetParent === null) {
            this.hide();
        }
        if (this.invokerElement) {
            const { top, left } = getAnchoredPosition(this.dialog, this.invokerElement, {
                align: this.align,
                side: this.side,
                anchorOffset: 4,
            });
            this.dialog.style.top = `${top}px`;
            this.dialog.style.left = `${left}px`;
            this.dialog.style.bottom = 'auto';
            this.dialog.style.right = 'auto';
        }
    }
    connectedCallback() {
        const { signal } = (__classPrivateFieldSet(this, _SelectPanelElement_abortController, new AbortController(), "f"));
        this.addEventListener('keydown', this, { signal });
        this.addEventListener('click', this, { signal });
        this.addEventListener('mousedown', this, { signal });
        this.addEventListener('input', this, { signal });
        this.addEventListener('remote-input-success', this, { signal });
        this.addEventListener('remote-input-error', this, { signal });
        this.addEventListener('loadstart', this, { signal });
        __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_setDynamicLabel).call(this);
        __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateInput).call(this);
        __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_softDisableItems).call(this);
        updateWhenVisible(this);
        observeMutationsUntilConditionMet(this, () => Boolean(this.remoteInput), () => {
            this.remoteInput.addEventListener('loadstart', this, { signal });
            this.remoteInput.addEventListener('loadend', this, { signal });
        });
        observeMutationsUntilConditionMet(this, () => Boolean(this.includeFragment), () => {
            this.includeFragment.addEventListener('include-fragment-replaced', this, { signal });
            this.includeFragment.addEventListener('error', this, { signal });
            this.includeFragment.addEventListener('loadend', this, { signal });
        });
        __classPrivateFieldSet(this, _SelectPanelElement_dialogIntersectionObserver, new IntersectionObserver(entries => {
            for (const entry of entries) {
                const elem = entry.target;
                if (entry.isIntersecting && elem === this.dialog) {
                    // Focus on the filter input when the dialog opens to work around a Safari limitation
                    // that prevents the autofocus attribute from working as it does in other browsers
                    if (this.filterInputTextField) {
                        if (document.activeElement !== this.filterInputTextField) {
                            this.filterInputTextField.focus();
                        }
                    }
                    // signal that any focus hijinks are finished (thanks Safari)
                    this.dialog.setAttribute('data-ready', 'true');
                    this.updateAnchorPosition();
                    if (__classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_fetchStrategy_get) === FetchStrategy.LOCAL) {
                        __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateItemVisibility).call(this);
                    }
                }
            }
        }), "f");
        observeMutationsUntilConditionMet(this, () => Boolean(this.dialog), () => {
            __classPrivateFieldGet(this, _SelectPanelElement_dialogIntersectionObserver, "f").observe(this.dialog);
            this.dialog.addEventListener('close', this, { signal });
            if (this.getAttribute('data-open-on-load') === 'true') {
                this.show();
            }
        });
        if (__classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_fetchStrategy_get) === FetchStrategy.LOCAL) {
            observeMutationsUntilConditionMet(this, () => this.items.length > 0, () => {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateItemVisibility).call(this);
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateInput).call(this);
            });
        }
    }
    disconnectedCallback() {
        __classPrivateFieldGet(this, _SelectPanelElement_abortController, "f").abort();
    }
    handleEvent(event) {
        if (event.target === this.filterInputTextField) {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleSearchFieldEvent).call(this, event);
            return;
        }
        if (event.target === this.remoteInput) {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleRemoteInputEvent).call(this, event);
            return;
        }
        const targetIsInvoker = this.invokerElement?.contains(event.target);
        const targetIsCloseButton = this.closeButton?.contains(event.target);
        const eventIsActivation = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_isActivation).call(this, event);
        if (targetIsInvoker && event.type === 'mousedown') {
            return;
        }
        if (event.type === 'mousedown' && event.target instanceof HTMLInputElement) {
            return;
        }
        // Prevent safari bug that dismisses menu on mousedown instead of allowing
        // the click event to propagate to the button
        if (event.type === 'mousedown') {
            event.preventDefault();
            return;
        }
        if (targetIsInvoker && eventIsActivation) {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleInvokerActivated).call(this, event);
            return;
        }
        if (targetIsCloseButton && eventIsActivation) {
            // hide() will automatically be called by dialog event triggered from `data-close-dialog-id`
            return;
        }
        if (event.target === this.dialog && event.type === 'close') {
            // Remove data-ready so it can be set the next time the panel is opened
            this.dialog.removeAttribute('data-ready');
            this.invokerElement?.setAttribute('aria-expanded', 'false');
            // When we close the dialog, clear the filter input
            if (this.filterInputTextField) {
                const fireSearchEvent = this.filterInputTextField.value.length > 0;
                this.filterInputTextField.value = '';
                if (fireSearchEvent) {
                    this.filterInputTextField.dispatchEvent(new Event('input'));
                }
            }
            this.dispatchEvent(new CustomEvent('panelClosed', {
                detail: { panel: this },
                bubbles: true,
            }));
            return;
        }
        const item = event.target.closest(visibleMenuItemSelectors)?.parentElement;
        const targetIsItem = item !== null && item !== undefined;
        if (targetIsItem && eventIsActivation) {
            if (__classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_potentiallyDisallowActivation).call(this, event))
                return;
            const dialogInvoker = item.closest('[data-show-dialog-id]');
            if (dialogInvoker) {
                const dialog = this.ownerDocument.getElementById(dialogInvoker.getAttribute('data-show-dialog-id') || '');
                if (dialog && this.contains(dialogInvoker) && this.contains(dialog)) {
                    __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleDialogItemActivated).call(this, event, dialog);
                    return;
                }
            }
            // Pressing the space key on a link will cause the page to scroll unless preventDefault() is called.
            // We then click it manually to navigate.
            if (__classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_isAnchorActivationViaSpace).call(this, event)) {
                event.preventDefault();
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item)?.click();
            }
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleItemActivated).call(this, item);
            return;
        }
        if (event.type === 'click') {
            const rect = this.dialog.getBoundingClientRect();
            const clickWasInsideDialog = rect.top <= event.clientY &&
                event.clientY <= rect.top + rect.height &&
                rect.left <= event.clientX &&
                event.clientX <= rect.left + rect.width;
            if (!clickWasInsideDialog) {
                this.hide();
            }
        }
        // The include fragment will have been removed from the DOM by the time
        // the include-fragment-replaced event has been dispatched, so we have to
        // check for the type of the event target manually, since this.includeFragment
        // will be null.
        if (event.target instanceof IncludeFragmentElement) {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleIncludeFragmentEvent).call(this, event);
        }
    }
    show() {
        this.updateAnchorPosition();
        this.dialog.showModal();
        this.invokerElement?.setAttribute('aria-expanded', 'true');
        const event = new CustomEvent('dialog:open', {
            detail: { dialog: this.dialog },
        });
        this.dispatchEvent(event);
    }
    hide() {
        this.dialog.close();
    }
    get visibleItems() {
        return Array.from(this.querySelectorAll(visibleMenuItemSelectors)).map(element => element.parentElement);
    }
    get items() {
        return Array.from(this.querySelectorAll(menuItemSelectors)).map(element => element.parentElement);
    }
    get focusableItem() {
        for (const item of this.items) {
            const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
            if (!itemContent)
                continue;
            if (itemContent.getAttribute('tabindex') === '0') {
                return itemContent;
            }
        }
    }
    getItemById(itemId) {
        return this.querySelector(`li[data-item-id="${itemId}"`);
    }
    isItemDisabled(item) {
        if (item) {
            return item.classList.contains('ActionListItem--disabled');
        }
        else {
            return false;
        }
    }
    disableItem(item) {
        if (item) {
            item.classList.add('ActionListItem--disabled');
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item).setAttribute('aria-disabled', 'true');
        }
    }
    enableItem(item) {
        if (item) {
            item.classList.remove('ActionListItem--disabled');
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item).removeAttribute('aria-disabled');
        }
    }
    isItemHidden(item) {
        if (item) {
            return item.hasAttribute('hidden');
        }
        else {
            return false;
        }
    }
    isItemChecked(item) {
        if (item) {
            return __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item).getAttribute(this.ariaSelectionType) === 'true';
        }
        else {
            return false;
        }
    }
    checkItem(item) {
        if (item && (this.selectVariant === 'single' || this.selectVariant === 'multiple')) {
            if (!this.isItemChecked(item)) {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleItemActivated).call(this, item);
            }
        }
    }
    uncheckItem(item) {
        if (item && (this.selectVariant === 'single' || this.selectVariant === 'multiple')) {
            if (this.isItemChecked(item)) {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_handleItemActivated).call(this, item);
            }
        }
    }
};
_SelectPanelElement_dialogIntersectionObserver = new WeakMap();
_SelectPanelElement_abortController = new WeakMap();
_SelectPanelElement_originalLabel = new WeakMap();
_SelectPanelElement_inputName = new WeakMap();
_SelectPanelElement_selectedItems = new WeakMap();
_SelectPanelElement_loadingDelayTimeoutId = new WeakMap();
_SelectPanelElement_loadingAnnouncementTimeoutId = new WeakMap();
_SelectPanelElement_hasLoadedData = new WeakMap();
_SelectPanelElement_instances = new WeakSet();
_SelectPanelElement_softDisableItems = function _SelectPanelElement_softDisableItems() {
    const { signal } = __classPrivateFieldGet(this, _SelectPanelElement_abortController, "f");
    for (const item of this.querySelectorAll(validSelectors.join(','))) {
        item.addEventListener('click', __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_potentiallyDisallowActivation).bind(this), { signal });
        item.addEventListener('keydown', __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_potentiallyDisallowActivation).bind(this), { signal });
    }
};
_SelectPanelElement_updateTabIndices = function _SelectPanelElement_updateTabIndices() {
    let setZeroTabIndex = false;
    if (this.selectVariant === 'single') {
        for (const item of this.items) {
            const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
            if (!itemContent)
                continue;
            if (!this.isItemHidden(item) && this.isItemChecked(item) && !setZeroTabIndex) {
                itemContent.setAttribute('tabindex', '0');
                setZeroTabIndex = true;
            }
            else {
                itemContent.setAttribute('tabindex', '-1');
            }
            // <li> elements should not themselves be tabbable
            item.removeAttribute('tabindex');
        }
    }
    else {
        for (const item of this.items) {
            const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
            if (!itemContent)
                continue;
            itemContent.setAttribute('tabindex', '-1');
            // <li> elements should not themselves be tabbable
            item.removeAttribute('tabindex');
        }
    }
    if (!setZeroTabIndex && __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_firstItem_get)) {
        __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_firstItem_get))?.setAttribute('tabindex', '0');
    }
};
_SelectPanelElement_potentiallyDisallowActivation = function _SelectPanelElement_potentiallyDisallowActivation(event) {
    if (!__classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_isActivation).call(this, event))
        return false;
    const item = event.target.closest(visibleMenuItemSelectors);
    if (!item)
        return false;
    if (item.getAttribute('aria-disabled')) {
        event.preventDefault();
        // eslint-disable-next-line no-restricted-syntax
        event.stopPropagation();
        // eslint-disable-next-line no-restricted-syntax
        event.stopImmediatePropagation();
        return true;
    }
    return false;
};
_SelectPanelElement_isAnchorActivationViaSpace = function _SelectPanelElement_isAnchorActivationViaSpace(event) {
    return (event.target instanceof HTMLAnchorElement &&
        event instanceof KeyboardEvent &&
        event.type === 'keydown' &&
        !(event.ctrlKey || event.altKey || event.metaKey || event.shiftKey) &&
        event.key === ' ');
};
_SelectPanelElement_isActivation = function _SelectPanelElement_isActivation(event) {
    // Some browsers fire MouseEvents (Firefox) and others fire PointerEvents (Chrome). Activating an item via
    // enter or space counterintuitively fires one of these rather than a KeyboardEvent. Since PointerEvent
    // inherits from MouseEvent, it is enough to check for MouseEvent here.
    return (event instanceof MouseEvent && event.type === 'click') || __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_isAnchorActivationViaSpace).call(this, event);
};
_SelectPanelElement_checkSelectedItems = function _SelectPanelElement_checkSelectedItems() {
    for (const item of this.items) {
        const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
        if (!itemContent)
            continue;
        const value = itemContent.getAttribute('data-value');
        if (value) {
            if (__classPrivateFieldGet(this, _SelectPanelElement_selectedItems, "f").has(value)) {
                itemContent.setAttribute(this.ariaSelectionType, 'true');
            }
        }
    }
    __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateInput).call(this);
};
_SelectPanelElement_addSelectedItem = function _SelectPanelElement_addSelectedItem(item) {
    const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
    if (!itemContent)
        return;
    const value = itemContent.getAttribute('data-value');
    if (value) {
        __classPrivateFieldGet(this, _SelectPanelElement_selectedItems, "f").set(value, {
            value,
            label: itemContent.querySelector('.ActionListItem-label')?.textContent?.trim(),
            inputName: itemContent.getAttribute('data-input-name'),
        });
    }
};
_SelectPanelElement_removeSelectedItem = function _SelectPanelElement_removeSelectedItem(item) {
    const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
    if (!itemContent)
        return;
    const value = itemContent.getAttribute('data-value');
    if (value) {
        __classPrivateFieldGet(this, _SelectPanelElement_selectedItems, "f").delete(value);
    }
};
_SelectPanelElement_setTextFieldLoadingSpinnerTimer = function _SelectPanelElement_setTextFieldLoadingSpinnerTimer() {
    if (!__classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_filterInputTextFieldElement_get))
        return;
    if (__classPrivateFieldGet(this, _SelectPanelElement_loadingDelayTimeoutId, "f"))
        clearTimeout(__classPrivateFieldGet(this, _SelectPanelElement_loadingDelayTimeoutId, "f"));
    if (__classPrivateFieldGet(this, _SelectPanelElement_loadingAnnouncementTimeoutId, "f"))
        clearTimeout(__classPrivateFieldGet(this, _SelectPanelElement_loadingAnnouncementTimeoutId, "f"));
    __classPrivateFieldSet(this, _SelectPanelElement_loadingAnnouncementTimeoutId, setTimeout(() => {
        this.liveRegion.announce('Loading');
    }, 2000), "f");
    __classPrivateFieldSet(this, _SelectPanelElement_loadingDelayTimeoutId, setTimeout(() => {
        __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_filterInputTextFieldElement_get)?.showLeadingSpinner();
    }, 1000), "f");
};
_SelectPanelElement_handleIncludeFragmentEvent = function _SelectPanelElement_handleIncludeFragmentEvent(event) {
    switch (event.type) {
        case 'include-fragment-replaced': {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateItemVisibility).call(this);
            break;
        }
        case 'loadstart': {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_toggleIncludeFragmentElements).call(this, false);
            break;
        }
        case 'loadend': {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_filterInputTextFieldElement_get)?.hideLeadingSpinner();
            this.dispatchEvent(new CustomEvent('loadend'));
            break;
        }
        case 'error': {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_toggleIncludeFragmentElements).call(this, true);
            const errorElement = this.fragmentErrorElement;
            // check if the errorElement is visible in the dom
            if (errorElement && !errorElement.hasAttribute('hidden')) {
                this.liveRegion.announceFromElement(errorElement, { politeness: 'assertive' });
                return;
            }
            break;
        }
    }
};
_SelectPanelElement_toggleIncludeFragmentElements = function _SelectPanelElement_toggleIncludeFragmentElements(showError) {
    for (const el of this.includeFragment.querySelectorAll('[data-show-on-error]')) {
        if (el instanceof HTMLElement)
            el.hidden = !showError;
    }
    for (const el of this.includeFragment.querySelectorAll('[data-hide-on-error]')) {
        if (el instanceof HTMLElement)
            el.hidden = showError;
    }
};
_SelectPanelElement_handleRemoteInputEvent = function _SelectPanelElement_handleRemoteInputEvent(event) {
    switch (event.type) {
        case 'remote-input-success': {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_clearErrorState).call(this);
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateItemVisibility).call(this);
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_checkSelectedItems).call(this);
            break;
        }
        case 'remote-input-error': {
            this.bodySpinner?.setAttribute('hidden', '');
            if (this.includeFragment || this.visibleItems.length === 0) {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_setErrorState).call(this, ErrorStateType.BODY);
            }
            else {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_setErrorState).call(this, ErrorStateType.BANNER);
            }
            break;
        }
        case 'loadstart': {
            if (!__classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_performFilteringLocally).call(this)) {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_clearErrorState).call(this);
                this.bodySpinner?.removeAttribute('hidden');
                if (this.bodySpinner)
                    break;
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_setTextFieldLoadingSpinnerTimer).call(this);
            }
            break;
        }
        case 'loadend': {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_filterInputTextFieldElement_get)?.hideLeadingSpinner();
            if (__classPrivateFieldGet(this, _SelectPanelElement_loadingAnnouncementTimeoutId, "f"))
                clearTimeout(__classPrivateFieldGet(this, _SelectPanelElement_loadingAnnouncementTimeoutId, "f"));
            if (__classPrivateFieldGet(this, _SelectPanelElement_loadingDelayTimeoutId, "f"))
                clearTimeout(__classPrivateFieldGet(this, _SelectPanelElement_loadingDelayTimeoutId, "f"));
            this.dispatchEvent(new CustomEvent('loadend'));
            break;
        }
    }
};
_SelectPanelElement_defaultFilterFn = function _SelectPanelElement_defaultFilterFn(item, query) {
    const text = (item.getAttribute('data-filter-string') || item.textContent || '').toLowerCase();
    return text.indexOf(query.toLowerCase()) > -1;
};
_SelectPanelElement_handleSearchFieldEvent = function _SelectPanelElement_handleSearchFieldEvent(event) {
    if (event.type === 'keydown') {
        const key = event.key;
        if (key === 'Enter') {
            const item = this.visibleItems[0];
            if (item) {
                const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
                if (itemContent)
                    itemContent.click();
            }
        }
        else if (key === 'ArrowDown') {
            const item = (this.focusableItem || __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, this.visibleItems[0]));
            if (item) {
                item.focus();
                event.preventDefault();
            }
        }
        else if (key === 'Home') {
            const item = this.visibleItems[0];
            if (item) {
                const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
                if (itemContent)
                    itemContent.focus();
                event.preventDefault();
            }
        }
        else if (key === 'End') {
            if (this.visibleItems.length > 0) {
                const item = this.visibleItems[this.visibleItems.length - 1];
                const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
                if (itemContent)
                    itemContent.focus();
                event.preventDefault();
            }
        }
    }
    if (event.type !== 'input')
        return;
    // remote-input-element does not trigger another loadstart event if a request is
    // already in-flight, so we use the input event on the text field to reset the
    // loading spinner timer instead
    if (!this.bodySpinner && !__classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_performFilteringLocally).call(this)) {
        __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_setTextFieldLoadingSpinnerTimer).call(this);
    }
    if (__classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_fetchStrategy_get) === FetchStrategy.LOCAL || __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_fetchStrategy_get) === FetchStrategy.EVENTUALLY_LOCAL) {
        if (this.includeFragment) {
            this.includeFragment.refetch();
            return;
        }
        __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateItemVisibility).call(this);
    }
};
_SelectPanelElement_updateItemVisibility = function _SelectPanelElement_updateItemVisibility() {
    if (!this.list)
        return;
    let atLeastOneResult = false;
    if (__classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_performFilteringLocally).call(this)) {
        const query = this.filterInputTextField?.value ?? '';
        const filter = this.filterFn || __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_defaultFilterFn);
        for (const item of this.items) {
            if (filter(item, query)) {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_showItem).call(this, item);
                atLeastOneResult = true;
            }
            else {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_hideItem).call(this, item);
            }
        }
    }
    else {
        atLeastOneResult = this.items.length > 0;
    }
    __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateTabIndices).call(this);
    __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_maybeAnnounce).call(this);
    for (const item of this.items) {
        const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
        if (!itemContent)
            continue;
        const value = itemContent.getAttribute('data-value');
        if (__classPrivateFieldGet(this, _SelectPanelElement_hasLoadedData, "f")) {
            if (value && !__classPrivateFieldGet(this, _SelectPanelElement_selectedItems, "f").has(value)) {
                itemContent.setAttribute(this.ariaSelectionType, 'false');
            }
        }
        else if (value && !__classPrivateFieldGet(this, _SelectPanelElement_selectedItems, "f").has(value) && this.isItemChecked(item)) {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_addSelectedItem).call(this, item);
        }
    }
    __classPrivateFieldSet(this, _SelectPanelElement_hasLoadedData, true, "f");
    if (!this.noResults)
        return;
    if (__classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_inErrorState).call(this)) {
        this.noResults.setAttribute('hidden', '');
        return;
    }
    if (atLeastOneResult) {
        this.noResults.setAttribute('hidden', '');
        // TODO can we change this to search for `@panelId-list`
        this.list?.querySelector('.ActionListWrap')?.removeAttribute('hidden');
    }
    else {
        this.list?.querySelector('.ActionListWrap')?.setAttribute('hidden', '');
        this.noResults.removeAttribute('hidden');
    }
};
_SelectPanelElement_inErrorState = function _SelectPanelElement_inErrorState() {
    if (this.fragmentErrorElement && !this.fragmentErrorElement.hasAttribute('hidden')) {
        return true;
    }
    if (!this.bannerErrorElement)
        return false;
    return !this.bannerErrorElement.hasAttribute('hidden');
};
_SelectPanelElement_setErrorState = function _SelectPanelElement_setErrorState(type) {
    let errorElement = this.fragmentErrorElement;
    if (type === ErrorStateType.BODY && this.fragmentErrorElement) {
        this.fragmentErrorElement.removeAttribute('hidden');
        this.bannerErrorElement.setAttribute('hidden', '');
    }
    else {
        errorElement = this.bannerErrorElement;
        this.bannerErrorElement?.removeAttribute('hidden');
        this.fragmentErrorElement?.setAttribute('hidden', '');
    }
    // check if the errorElement is visible in the dom
    if (errorElement && !errorElement.hasAttribute('hidden')) {
        this.liveRegion.announceFromElement(errorElement, { politeness: 'assertive' });
        return;
    }
};
_SelectPanelElement_clearErrorState = function _SelectPanelElement_clearErrorState() {
    this.fragmentErrorElement?.setAttribute('hidden', '');
    this.bannerErrorElement.setAttribute('hidden', '');
};
_SelectPanelElement_maybeAnnounce = function _SelectPanelElement_maybeAnnounce() {
    if (this.open && this.list) {
        const items = this.visibleItems;
        if (items.length > 0) {
            const instructions = 'tab for results';
            this.liveRegion.announce(`${items.length} result${items.length === 1 ? '' : 's'} ${instructions}`);
        }
        else {
            const noResultsEl = this.noResults;
            if (noResultsEl) {
                this.liveRegion.announceFromElement(noResultsEl);
            }
        }
    }
};
_SelectPanelElement_fetchStrategy_get = function _SelectPanelElement_fetchStrategy_get() {
    if (!this.list)
        return FetchStrategy.REMOTE;
    switch (this.list.getAttribute('data-fetch-strategy')) {
        case 'local':
            return FetchStrategy.LOCAL;
        case 'eventually_local':
            return FetchStrategy.EVENTUALLY_LOCAL;
        default:
            return FetchStrategy.REMOTE;
    }
};
_SelectPanelElement_filterInputTextFieldElement_get = function _SelectPanelElement_filterInputTextFieldElement_get() {
    return this.filterInputTextField?.closest('primer-text-field');
};
_SelectPanelElement_performFilteringLocally = function _SelectPanelElement_performFilteringLocally() {
    return __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_fetchStrategy_get) === FetchStrategy.LOCAL || __classPrivateFieldGet(this, _SelectPanelElement_instances, "a", _SelectPanelElement_fetchStrategy_get) === FetchStrategy.EVENTUALLY_LOCAL;
};
_SelectPanelElement_handleInvokerActivated = function _SelectPanelElement_handleInvokerActivated(event) {
    event.preventDefault();
    // eslint-disable-next-line no-restricted-syntax
    event.stopPropagation();
    if (this.open) {
        this.hide();
    }
    else {
        this.show();
    }
};
_SelectPanelElement_handleDialogItemActivated = function _SelectPanelElement_handleDialogItemActivated(event, dialog) {
    this.querySelector('.ActionListWrap').style.display = 'none';
    const dialog_controller = new AbortController();
    const { signal } = dialog_controller;
    const handleDialogClose = () => {
        dialog_controller.abort();
        this.querySelector('.ActionListWrap').style.display = '';
        if (this.open) {
            this.hide();
        }
        const activeElement = this.ownerDocument.activeElement;
        const lostFocus = this.ownerDocument.activeElement === this.ownerDocument.body;
        const focusInClosedMenu = this.contains(activeElement);
        if (lostFocus || focusInClosedMenu) {
            setTimeout(() => this.invokerElement?.focus(), 0);
        }
    };
    // a modal <dialog> element will close all popovers
    dialog.addEventListener('close', handleDialogClose, { signal });
    dialog.addEventListener('cancel', handleDialogClose, { signal });
};
_SelectPanelElement_handleItemActivated = function _SelectPanelElement_handleItemActivated(item) {
    // Hide popover after current event loop to prevent changes in focus from
    // altering the target of the event. Not doing this specifically affects
    // <a> tags. It causes the event to be sent to the currently focused element
    // instead of the anchor, which effectively prevents navigation, i.e. it
    // appears as if hitting enter does nothing. Curiously, clicking instead
    // works fine.
    if (this.selectVariant !== 'multiple') {
        setTimeout(() => {
            if (this.open) {
                this.hide();
            }
        });
    }
    // The rest of the code below deals with single/multiple selection behavior, and should not
    // interfere with events fired by menu items whose behavior is specified outside the library.
    if (this.selectVariant !== 'multiple' && this.selectVariant !== 'single')
        return;
    const currentlyChecked = this.isItemChecked(item);
    const checked = !currentlyChecked;
    const activationSuccess = this.dispatchEvent(new CustomEvent('beforeItemActivated', {
        bubbles: true,
        cancelable: true,
        detail: {
            item,
            checked,
            value: __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item)?.getAttribute('data-value'),
        },
    }));
    if (!activationSuccess)
        return;
    const itemContent = __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item);
    if (this.selectVariant === 'single') {
        // Don't check anything if we have an href
        if (itemContent?.getAttribute('href'))
            return;
        // disallow unchecking checked item in single-select mode
        if (!currentlyChecked) {
            for (const el of this.items) {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, el)?.setAttribute(this.ariaSelectionType, 'false');
            }
            __classPrivateFieldGet(this, _SelectPanelElement_selectedItems, "f").clear();
            if (checked) {
                __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_addSelectedItem).call(this, item);
                itemContent?.setAttribute(this.ariaSelectionType, 'true');
            }
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_setDynamicLabel).call(this);
        }
    }
    else {
        // multi-select mode allows unchecking a checked item
        itemContent?.setAttribute(this.ariaSelectionType, `${checked}`);
        if (checked) {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_addSelectedItem).call(this, item);
        }
        else {
            __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_removeSelectedItem).call(this, item);
        }
    }
    __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateInput).call(this);
    __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_updateTabIndices).call(this);
    this.dispatchEvent(new CustomEvent('itemActivated', {
        bubbles: true,
        detail: {
            item,
            checked,
            value: __classPrivateFieldGet(this, _SelectPanelElement_instances, "m", _SelectPanelElement_getItemContent).call(this, item)?.getAttribute('data-value'),
        },
    }));
};
_SelectPanelElement_setDynamicLabel = function _SelectPanelElement_setDynamicLabel() {
    if (!this.dynamicLabel)
        return;
    const invokerLabel = this.invokerLabel;
    if (!invokerLabel)
        return;
    __classPrivateFieldSet(this, _SelectPanelElement_originalLabel, __classPrivateFieldGet(this, _SelectPanelElement_originalLabel, "f") || (invokerLabel.textContent || ''), "f");
    const itemLabel = this.querySelector(`[${this.ariaSelectionType}=true] .ActionListItem-label`)?.textContent || __classPrivateFieldGet(this, _SelectPanelElement_originalLabel, "f");
    if (itemLabel) {
        const prefixSpan = document.createElement('span');
        prefixSpan.classList.add('color-fg-muted');
        const contentSpan = document.createElement('span');
        prefixSpan.textContent = `${this.dynamicLabelPrefix} `;
        contentSpan.textContent = itemLabel;
        invokerLabel.replaceChildren(prefixSpan, contentSpan);
        if (this.dynamicAriaLabelPrefix) {
            this.invokerElement?.setAttribute('aria-label', `${this.dynamicAriaLabelPrefix} ${itemLabel.trim()}`);
        }
    }
    else {
        invokerLabel.textContent = __classPrivateFieldGet(this, _SelectPanelElement_originalLabel, "f");
    }
};
_SelectPanelElement_updateInput = function _SelectPanelElement_updateInput() {
    if (this.selectVariant === 'single') {
        const input = this.querySelector(`[data-list-inputs=true] input`);
        if (!input)
            return;
        const selectedItem = this.selectedItems[0];
        if (selectedItem) {
            input.value = (selectedItem.value || selectedItem.label || '').trim();
            if (selectedItem.inputName)
                input.name = selectedItem.inputName;
            input.removeAttribute('disabled');
        }
        else {
            input.setAttribute('disabled', 'disabled');
        }
    }
    else if (this.selectVariant !== 'none') {
        // multiple select variant
        const inputList = this.querySelector('[data-list-inputs=true]');
        if (!inputList)
            return;
        const inputs = inputList.querySelectorAll('input');
        if (inputs.length > 0) {
            __classPrivateFieldSet(this, _SelectPanelElement_inputName, __classPrivateFieldGet(this, _SelectPanelElement_inputName, "f") || inputs[0].name, "f");
        }
        for (const selectedItem of this.selectedItems) {
            const newInput = document.createElement('input');
            newInput.setAttribute('data-list-input', 'true');
            newInput.type = 'hidden';
            newInput.autocomplete = 'off';
            newInput.name = selectedItem.inputName || __classPrivateFieldGet(this, _SelectPanelElement_inputName, "f");
            newInput.value = (selectedItem.value || selectedItem.label || '').trim();
            inputList.append(newInput);
        }
        for (const input of inputs) {
            input.remove();
        }
    }
};
_SelectPanelElement_firstItem_get = function _SelectPanelElement_firstItem_get() {
    return (this.querySelector(visibleMenuItemSelectors)?.parentElement || null);
};
_SelectPanelElement_hideItem = function _SelectPanelElement_hideItem(item) {
    if (item) {
        item.setAttribute('hidden', 'hidden');
    }
};
_SelectPanelElement_showItem = function _SelectPanelElement_showItem(item) {
    if (item) {
        item.removeAttribute('hidden');
    }
};
_SelectPanelElement_getItemContent = function _SelectPanelElement_getItemContent(item) {
    return item.querySelector('.ActionListContent');
};
__decorate([
    target
], SelectPanelElement.prototype, "includeFragment", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "dialog", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "filterInputTextField", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "remoteInput", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "list", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "noResults", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "fragmentErrorElement", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "bannerErrorElement", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "bodySpinner", void 0);
__decorate([
    target
], SelectPanelElement.prototype, "liveRegion", void 0);
SelectPanelElement = __decorate([
    controller
], SelectPanelElement);
export { SelectPanelElement };
if (!window.customElements.get('select-panel')) {
    window.SelectPanelElement = SelectPanelElement;
    window.customElements.define('select-panel', SelectPanelElement);
}
