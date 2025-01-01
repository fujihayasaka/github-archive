import { attr, controller, target, targets } from '@github/catalyst'
import { TemplateInstance } from '@github/template-parts'

@controller
export class FormTableElement extends HTMLElement {
  // What's data-index-name for?
  // If we have two nested templates using index in the way that vulnerabilities or affected functions do,
  // the overlapping name can cause mis templating of the {{index}} value, so we make sure that nested views
  // use a different templated name for index.
  @attr dataIndexName: string
  @target rowTemplate: HTMLTemplateElement
  @target body: HTMLElement
  @targets rows: FormTableRowElement[]

  connectedCallback() {
    this.ensureVisibleRow()
    this.dispatchEvent(new CustomEvent('initialized'))
  }

  addRow(focus = true, templateData?: object): FormTableRowElement {
    const generatedTemplateData = this.generateTemplateData(templateData)
    const templateInstance = new TemplateInstance(
      this.rowTemplate,
      generatedTemplateData,
    )
    this.body.appendChild(templateInstance)
    const newRow = this.rows[this.rows.length - 1]
    if (focus) {
      newRow.firstFocus?.focus()
    }

    return newRow
  }

  generateTemplateData(templateData) {
    let data = {}
    const targetIndex = this.rows.length

    data[this.dataIndexName ?? 'index'] = targetIndex
    if (templateData) {
      data = Object.assign(data, templateData)
    }
    return data
  }

  ensureVisibleRow(event?: CustomEvent) {
    const visibleRows = this.rows.filter((row) => {
      return !(row.hidden || row === event?.detail)
    })

    if (!visibleRows.length) {
      this.addRow(false)
    }
  }

  cloneRow(event: CustomEvent) {
    const rowInputs = event.detail.inputs
    const clone = this.addRow()

    for (const [i, rowInput] of rowInputs.entries()) {
      const cloneInput = clone.inputs[i]
      cloneInput.value = rowInput.value
      if (rowInput.checked) {
        cloneInput.click() // setting checked by UI for any interactive form elements with callbacks
      } else if (rowInput.value.length > 0) {
        // trigger any associated callbacks
        const change = new Event('change')
        cloneInput.dispatchEvent(change)
      }
    }

    // Tell the source element what the new index is
    event.detail.dispatchEvent(
      new CustomEvent('rowCloned', { detail: { index: clone.dataIndex } }),
    )
  }
}

@controller
export class FormTableRowElement extends HTMLElement {
  @attr dataIndex
  @target deletionCheckbox: HTMLInputElement
  @target firstFocus: HTMLInputElement
  @targets inputs: HTMLInputElement[]

  delete() {
    this.dispatchEvent(new CustomEvent('deleteRow', { detail: this }))
    if (this.deletionCheckbox) {
      if (!this.deletionCheckbox.checked) {
        this.deletionCheckbox.click()
      }
      this.setAttribute('hidden', '')
    } else {
      this.remove()
    }
  }

  clone() {
    this.dispatchEvent(new CustomEvent('cloneRow', { detail: this }))
  }
}
