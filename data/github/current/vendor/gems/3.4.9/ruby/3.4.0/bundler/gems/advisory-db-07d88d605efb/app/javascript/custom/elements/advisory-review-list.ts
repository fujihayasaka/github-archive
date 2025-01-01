import { attr, controller, target, targets } from '@github/catalyst'
import { html, render } from '@github/jtml'

interface ErrorHash {
  [key: string]: string
}

@controller
export class AdvisoryReviewListElement extends HTMLElement {
  @attr dataAdvisoryReviewsBulkCloseUrl: string
  @attr dataAdvisoryReviewsBulkAssignUrl: string
  @attr dataAdvisoryReviewsBulkEcosystemAndPackageNameUrl: string
  @attr dataAdvisoryReviewsBulkLabelOptionsUrl: string
  @attr dataAdvisoryReviewsBulkLabelsUrl: string

  @target multiSelectEcosystemApplyButton: HTMLButtonElement
  @targets multiSelectIndividualEcosystems: HTMLElement[]
  @target multiSelectPackageNameInput: HTMLElement

  @target labelOptions: HTMLDivElement
  @target labelOptionsLoading: HTMLDivElement
  @target labelOptionsError: HTMLDivElement

  @target operationFeedbackPane: HTMLElement
  @target operationFeedback: HTMLInputElement
  @target operationSuccessIcon: HTMLElement
  @target operationFailureIcon: HTMLElement

  @target navigationStatus: HTMLElement
  @target navigationStatusFlash: HTMLElement

  @target confirmationDialogShowButton: HTMLButtonElement
  @target confirmationDialogContent: HTMLElement
  @target confirmationDialogSubmitButton: HTMLButtonElement

  csrfParam: string
  currentSelectedGHSAIDs: string[]
  // These are currently updated by the same action and both pertain to the same control
  currentMultiSelectEcosystemPackageName: {
    ecosystem: string | null
    packageName: string | null
  } = { ecosystem: null, packageName: null }

  constructor() {
    super()
  }

  connectedCallback() {
    this.loadBulkSuccessMessageIfNeeded()
    this.csrfParam = (
      document.querySelector('meta[name=csrf-token]') as HTMLMetaElement
    )?.content
  }

  onSelectionChanged(event: CustomEvent<{ selectedKeys: string[] }>) {
    this.currentSelectedGHSAIDs = event.detail.selectedKeys
    this.fetchBulkLabelOptions()
  }

  closeAllClicked() {
    this.confirmationDialogContent.textContent = `You are about to close the following advisories, are you sure you'd like to proceed? \n ${this.currentSelectedGHSAIDs.join(
      ', ',
    )}`
    this.confirmationDialogSubmitButton.setAttribute(
      'data-action',
      'click:advisory-review-list#closeAllConfirmed',
    )
    this.confirmationDialogShowButton.click()
  }

  async closeAllConfirmed() {
    let errorMessage = ''

    try {
      errorMessage = await this.takeBulkAction(
        this.dataAdvisoryReviewsBulkCloseUrl,
      )
    } catch (error) {
      errorMessage = error
    }

    this.setFeedbackMessageAndReloadIfNeeded(
      errorMessage || 'All advisory reviews closed successfully.',
      !!errorMessage,
    )
  }

  setEcosystemAndPackageName() {
    const ecosystem = this.currentMultiSelectEcosystemPackageName.ecosystem
    const packageName = this.currentMultiSelectEcosystemPackageName.packageName

    let trustedContent = ''
    if (packageName) {
      trustedContent = html`You are about to assign the ecosystem
      ${this.embolden(ecosystem)} and package name ${this.embolden(packageName)}
      to the following advisories, are you sure you'd like to proceed?
      ${this.lineBreak()} ${this.currentSelectedGHSAIDs.join(', ')}`
    } else {
      trustedContent = html`You are about to assign the ecosystem
      ${this.embolden(ecosystem)} to the following advisories, are you sure
      you'd like to proceed? ${this.lineBreak()}
      ${this.currentSelectedGHSAIDs.join(', ')}`
    }
    this.confirmationDialogContent.replaceChildren()
    render(trustedContent, this.confirmationDialogContent)

    this.confirmationDialogSubmitButton.setAttribute(
      'data-action',
      'click:advisory-review-list#setEcosystemAndPackageNameConfirmed',
    )
    this.confirmationDialogShowButton.click()
  }

  async setEcosystemAndPackageNameConfirmed() {
    let errorMessage = ''

    try {
      const ecosystem = this.currentMultiSelectEcosystemPackageName.ecosystem
      if (!ecosystem) {
        throw new Error(
          'Ecosystem must be specified to call setEcosystemAndPackageName',
        )
      }

      errorMessage = await this.takeBulkAction(
        this.dataAdvisoryReviewsBulkEcosystemAndPackageNameUrl,
        {
          ecosystem,
          packageName: this.currentMultiSelectEcosystemPackageName.packageName,
        },
      )
    } catch (error) {
      errorMessage = error
    }

    this.setFeedbackMessageAndReloadIfNeeded(
      errorMessage ||
        'All advisory reviews had ecosystem and package name set successfully.',
      !!errorMessage,
    )
  }

  assignClicked(event: PointerEvent) {
    const eventTarget = event.target as HTMLElement
    const slot = eventTarget.getAttribute('data-slot')!
    const curator = eventTarget.getAttribute('data-curator')!
    this.confirmationDialogContent.replaceChildren()
    render(
      html`You are about to assign the curator ${this.embolden(curator)} to slot
      ${this.embolden(slot)} for the following advisories, are you sure you'd
      like to proceed? ${this.lineBreak()}
      ${this.currentSelectedGHSAIDs.join(', ')}`,
      this.confirmationDialogContent,
    )

    this.confirmationDialogSubmitButton.setAttribute(
      'data-action',
      'click:advisory-review-list#assignConfirmed',
    )
    this.confirmationDialogSubmitButton.setAttribute('data-slot', slot)
    this.confirmationDialogSubmitButton.setAttribute('data-curator', curator)
    this.confirmationDialogShowButton.click()
  }

  async assignConfirmed(event: PointerEvent) {
    const eventTarget = event.target as HTMLElement
    const slot = eventTarget.getAttribute('data-slot')
    const curator = eventTarget.getAttribute('data-curator')
    let errorMessage = ''

    try {
      errorMessage = await this.takeBulkAction(
        this.dataAdvisoryReviewsBulkAssignUrl,
        {
          assignTo: curator === 'Unassign' ? null : curator,
          assignToSlot: slot,
        },
      )
    } catch (error) {
      errorMessage = error
    }

    this.setFeedbackMessageAndReloadIfNeeded(
      errorMessage || 'All advisory reviews assigned successfully.',
      !!errorMessage,
    )
  }

  async fetchBulkLabelOptions() {
    this.labelOptions.textContent = ''
    this.labelOptionsError.setAttribute('hidden', 'hidden')
    this.labelOptionsLoading.removeAttribute('hidden')

    const response = await fetch(this.dataAdvisoryReviewsBulkLabelOptionsUrl, {
      method: 'POST',
      body: JSON.stringify({ ghsaIds: this.currentSelectedGHSAIDs.join(',') }),
      headers: {
        'x-csrf-token': this.csrfParam,
      },
    })

    if (response.ok) {
      const options = await response.text()
      this.labelOptionsLoading.setAttribute('hidden', 'hidden')
      this.labelOptionsError.setAttribute('hidden', 'hidden')
      // eslint-disable-next-line github/no-inner-html
      this.labelOptions.innerHTML = options
    } else {
      this.labelOptionsLoading.setAttribute('hidden', 'hidden')
      this.labelOptions.textContent = ''
      this.labelOptionsError.removeAttribute('hidden')
    }
  }

  setLabels(event: CustomEvent) {
    this.confirmationDialogContent.textContent = `You are about to update labels on the following advisories, are you sure you'd like to proceed? \n ${this.currentSelectedGHSAIDs.join(
      ', ',
    )}`
    this.confirmationDialogSubmitButton.setAttribute(
      'data-action',
      'click:advisory-review-list#setLabelsConfirmed',
    )
    this.confirmationDialogSubmitButton.setAttribute(
      'data-label-ids',
      event.detail.labelIds.join(','),
    )
    this.confirmationDialogShowButton.click()
  }

  async setLabelsConfirmed() {
    const labelIds =
      this.confirmationDialogSubmitButton.getAttribute('data-label-ids')
    let errorMessage = ''

    try {
      errorMessage = await this.takeBulkAction(
        this.dataAdvisoryReviewsBulkLabelsUrl,
        { labelIds },
      )
    } catch (error) {
      errorMessage = error
    }

    this.setFeedbackMessageAndReloadIfNeeded(
      errorMessage || 'All labels updated successfully.',
      !!errorMessage,
    )
  }

  async takeBulkAction(url: string, params: object = {}) {
    const defaultParams = { ghsaIds: this.currentSelectedGHSAIDs.join(',') }
    const response = await fetch(url, {
      method: 'POST',
      body: JSON.stringify({ ...defaultParams, ...params }),
      headers: {
        'x-csrf-token': this.csrfParam,
      },
    })
    const jsonData = await response.json()

    if (!response.ok) {
      throw new Error(
        `Call to bulk action ${url.split('/')[-1]} failed! Error contents: ${
          jsonData.error
        }`,
      )
    }

    const errorMessages = Object.values(jsonData.errorHash as ErrorHash)
    return errorMessages.join('\n')
  }

  resetBulkOperations() {
    this.fetchBulkLabelOptions()
  }

  setFeedbackMessageAndReloadIfNeeded(msg: string, errorHappened: boolean) {
    if (!errorHappened) {
      sessionStorage.setItem('advisory-review-list-success-message', msg)
      location.reload()
    } else {
      this.operationFeedbackPane.removeAttribute('hidden')
      this.operationFailureIcon.removeAttribute('hidden')
      this.operationFeedback.textContent =
        `An error occurred, and some of the bulk operations you tried may have completed, while others may be incomplete. ` +
        `This view may show outdated information but isn't being refreshed automatically to help understand what happened. \n${msg}`
    }
  }

  loadBulkSuccessMessageIfNeeded() {
    const successMessage = sessionStorage.getItem(
      'advisory-review-list-success-message',
    )
    if (successMessage) {
      sessionStorage.removeItem('advisory-review-list-success-message')
      this.navigationStatus.textContent = successMessage
      this.navigationStatusFlash.hidden = false
    }
  }

  multiSelectEcosystemPackageNameChanged(event: Event) {
    const element = event.target as HTMLInputElement
    this.currentMultiSelectEcosystemPackageName = {
      ecosystem: this.currentMultiSelectEcosystemPackageName.ecosystem,
      packageName: element.value,
    }
  }

  multiSelectEcosystemSelection(event: Event) {
    const eventTarget = event.target as HTMLElement

    for (const ecosystemItem of this.multiSelectIndividualEcosystems) {
      const checkmark = ecosystemItem.querySelector(
        '.octicon-check',
      ) as HTMLElement
      checkmark.classList.remove('v-visible')
      checkmark.classList.add('v-hidden')
    }

    const ecosystemItem = eventTarget.closest(
      '.SelectMenu-item.ecosystem-item',
    ) as HTMLElement
    const ecosystemName = ecosystemItem.getAttribute('data-ecosystem-key')!
    this.currentMultiSelectEcosystemPackageName = {
      ecosystem: ecosystemName,
      packageName: this.currentMultiSelectEcosystemPackageName.packageName,
    }

    const checkmark = ecosystemItem.querySelector(
      '.octicon-check',
    ) as HTMLElement
    checkmark.classList.remove('v-hidden')
    checkmark.classList.add('v-visible')

    this.multiSelectEcosystemApplyButton.removeAttribute('disabled')
    this.multiSelectPackageNameInput.removeAttribute('disabled')
  }

  embolden(word) {
    const frag = document.createDocumentFragment()
    const strong = document.createElement('strong')
    strong.append(String(word))
    frag.append(strong)
    return frag
  }

  lineBreak() {
    const frag = document.createDocumentFragment()
    const lineBreak = document.createElement('br')
    frag.append(lineBreak)
    return frag
  }
}
