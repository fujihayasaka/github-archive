import { controller, target, targets } from '@github/catalyst'
import { TemplateInstance } from '@github/template-parts'

@controller
export class CWEAutocompleteElement extends HTMLElement {
  @target autoCompleteInput: HTMLInputElement
  @target linkedCWETemplate: HTMLTemplateElement
  @target linkedCWEList: HTMLDListElement
  @targets linkedCWEs: HTMLElement[]

  addLinkedCWE(event: CustomEvent) {
    // Need to stop propagation, otherwise the combobox-commit event populates the input field when clicked on after this function is run
    event.stopImmediatePropagation()

    const selectedCWE = event.currentTarget as HTMLElement
    if (selectedCWE) {
      const cwe_id = selectedCWE.getAttribute('data-autocomplete-value') || ''
      const cwe_name = selectedCWE.getAttribute('data-autocomplete-name') || ''

      if (cwe_name && cwe_id && this.canLinkCWE(cwe_id)) {
        this.addCWELink(cwe_id, cwe_name)
      }
    }

    this.autoCompleteInput.value = ''
    this.autoCompleteInput.focus()
  }

  removeLinkedCWE(event: CustomEvent) {
    const cwe = (event.target as Element).closest<HTMLElement>('.js-cwe-link')!
    cwe.remove()
  }

  // Checks for duplicate linked CWEs and returns true if CWE is not a duplicate
  canLinkCWE(cwe_id: string) {
    return this.linkedCWEs.every(
      (cwe) => cwe.getAttribute('data-cwe-id') !== cwe_id,
    )
  }

  addCWELink(cwe_id: string, cwe_name: string) {
    const linkedCWE = new TemplateInstance(this.linkedCWETemplate, {
      cwe_id,
      cwe_name,
    })

    this.linkedCWEList.append(linkedCWE)
  }
}
