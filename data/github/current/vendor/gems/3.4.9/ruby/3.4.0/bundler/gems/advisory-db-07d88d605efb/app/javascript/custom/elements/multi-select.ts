import { attr, controller, target, targets } from '@github/catalyst'

export class MultiSelectChangedEventPayload {
  public currentSelection: HTMLInputElement[]

  public constructor(init?: Partial<{ currentSelection: HTMLInputElement[] }>) {
    Object.assign(this, init)
  }
}

@controller
export class MultiSelectElement extends HTMLElement {
  @targets selectionCells: HTMLInputElement[]
  @target allSelectionCell: HTMLInputElement
  @attr dataAttributeForKey: string

  @targets visibleWhenMultiSelecting: HTMLElement[]
  @targets hiddenWhenMultiSelecting: HTMLElement[]

  connectedCallback() {
    this.rehydrateSelectedKeys()
  }

  storeSelectedKeys(selectedKeys: string[]) {
    sessionStorage[`selection_${this.dataAttributeForKey}`] =
      selectedKeys.join('|')
  }

  rehydrateSelectedKeys() {
    const storedKeys = sessionStorage[`selection_${this.dataAttributeForKey}`]
    const selectedKeys: string[] = (storedKeys || '').split('|')
    for (const cell of this.selectionCells) {
      const attributeForKey = cell.getAttribute(this.dataAttributeForKey)
      if (attributeForKey == null) {
        continue
      }
      cell.checked = selectedKeys.includes(attributeForKey)
    }

    this.sendSelectedEvent()
  }

  getSelectedKeys(): string[] {
    return this.selectionCells
      .map(
        (c) => c.checked === true && c.getAttribute(this.dataAttributeForKey),
      )
      .filter((s): s is string => !!s)
  }

  multiSelectClick() {
    const selectedCells = this.selectionCells.filter(
      (cell) => cell.checked === true,
    )
    this.allSelectionCell.checked =
      selectedCells.length === this.selectionCells.length

    this.sendSelectedEvent()
  }

  multiSelectAllClick() {
    const selectedCells = this.selectionCells.filter(
      (cell) => cell.checked === true,
    )
    const targetSelectionValue =
      selectedCells.length !== this.selectionCells.length
    for (const cell of this.selectionCells) {
      cell.checked = targetSelectionValue
    }

    this.sendSelectedEvent()
  }

  sendSelectedEvent() {
    const selectedKeys = this.getSelectedKeys()
    this.storeSelectedKeys(selectedKeys)
    this.adjustElementVisibility()
    const currentlySelectedCells = this.selectionCells.filter(
      (cell) => cell.checked === true,
    )
    this.dispatchEvent(
      new CustomEvent<{
        currentSelection: HTMLInputElement[]
        selectedKeys: string[]
      }>('multiSelectChanged', {
        detail: {
          currentSelection: currentlySelectedCells,
          selectedKeys,
        },
      }),
    )
  }

  adjustElementVisibility() {
    const isSelecting = this.getSelectedKeys().length > 0
    for (const e of this.visibleWhenMultiSelecting) {
      if (isSelecting) {
        e.removeAttribute('hidden')
      } else {
        e.setAttribute('hidden', 'hidden')
      }
    }
    for (const e of this.hiddenWhenMultiSelecting) {
      if (isSelecting) {
        e.setAttribute('hidden', 'hidden')
      } else {
        e.removeAttribute('hidden')
      }
    }
  }
}
