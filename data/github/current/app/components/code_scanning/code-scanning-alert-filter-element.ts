import type {Suggestion} from '../../assets/modules/github/filter-input'
import {BaseFilterElement} from '../../assets/modules/github/filter-input'
import {controller} from '@github/catalyst'

@controller
class CodeScanningAlertFilterElement extends BaseFilterElement {
  override selectorOfElementToActivateOnBlur = '.js-alert-list'

  override async fetchSuggestionsForQualifier(qualifier: string): Promise<Suggestion[]> {
    switch (this.removeNegationFromQualifierIfSupported(qualifier)) {
      case 'branch':
        return this.fetchSuggestionsForBranchQualifier()
      default:
        return super.fetchSuggestionsForQualifier(qualifier)
    }
  }

  // Retrieves the suggested refs, extracts any related to branches
  // (not tags) and returns new suggestions that are those branches'
  // names (excluding the 'refs/heads/' prefix)
  async fetchSuggestionsForBranchQualifier(): Promise<Suggestion[]> {
    const refSuggestions = await this.fetchSuggestionsForQualifier('ref')
    const branchNameSuggestions = []
    const branchRefPrefix = 'refs/heads/'
    for (const suggestion of refSuggestions) {
      if (suggestion.value.startsWith(branchRefPrefix)) {
        branchNameSuggestions.push({value: suggestion.value.substring(branchRefPrefix.length)})
      }
    }

    return branchNameSuggestions
  }

  override invalidSearchTerms(): string | null {
    const validQualifiers = this.fetchQualifierSuggestions().map(q => q.value)
    const parts = this.searchInput.value.match(/[^\s:]+:(?:"(?:\\"|.)*?"|[^\s]*)|[^\s]+/g) || []

    const invalidParts = parts.filter(part => {
      const colonIndex = part.indexOf(':')

      if (colonIndex === -1) {
        // It's free text so never invalid
        return false
      } else {
        // If we have typed a ':', it must fully match a valid qualifier
        const typedQualifier = this.removeNegationFromQualifierIfSupported(part.substr(0, colonIndex + 1))
        return !validQualifiers.some(validQualifier => validQualifier === typedQualifier)
      }
    })

    if (invalidParts.length === 0) {
      return null
    }

    return invalidParts.join(' ')
  }
}
