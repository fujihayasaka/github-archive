import {controller, target} from '@github/catalyst'

@controller
export class IntegrationAgentFormElement extends HTMLElement {
  MAX_SKILLS: number = 5

  @target declare agent: HTMLDivElement | undefined
  @target declare skills: HTMLDivElement | undefined
  @target declare common: HTMLDivElement | undefined
  @target declare switcher: HTMLInputElement | undefined
  @target declare skillsList: HTMLDivElement | undefined
  @target declare skillsBlankslate: HTMLDivElement | undefined
  @target declare skillsNewButton: HTMLDivElement | undefined
  @target declare blankSkill: HTMLDivElement | undefined
  @target declare disabledBanner: HTMLDivElement | undefined
  @target declare oidcFieldsToggle: HTMLInputElement | undefined
  @target declare oidcFields: HTMLDivElement | undefined

  connectedCallback() {
    this.switchForm()
  }

  switchForm() {
    if (!this.agent || !this.switcher || !this.skills || !this.common) {
      return
    }

    switch (this.switcher.value) {
      case 'agent':
        this.agent.hidden = false
        this.skills.hidden = true
        this.common.hidden = false
        if (this.disabledBanner) {
          this.disabledBanner.hidden = true
        }
        break
      case 'skill':
        this.agent.hidden = true
        this.skills.hidden = false
        this.common.hidden = false
        if (this.disabledBanner) {
          this.disabledBanner.hidden = true
        }
        break
      case 'disabled':
        this.agent.hidden = true
        this.skills.hidden = true
        this.common.hidden = true
        if (this.disabledBanner) {
          this.disabledBanner.hidden = false
        }
        break
    }
  }

  saveSkillFromDialog(skill: Element, dialog: Element) {
    const nameField = dialog.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-form-name-field]')
    const hiddenNameField = skill.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-name-field]')
    const nameTitle = skill.querySelector('[data-integration-agent-form=skill-name-title]')
    if (!nameField || !hiddenNameField || !nameTitle) {
      return
    }
    hiddenNameField.value = nameField.value
    nameTitle.textContent = nameField.value
    nameField.value = ''

    const descriptionField = dialog.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-form-description-field]',
    )
    const hiddenDescriptionField = skill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-description-field]',
    )
    const descriptionTitle = skill.querySelector('[data-integration-agent-form=skill-description-title]')
    if (!descriptionField || !hiddenDescriptionField || !descriptionTitle) {
      return
    }
    hiddenDescriptionField.value = descriptionField.value
    descriptionTitle.textContent = descriptionField.value
    descriptionField.value = ''

    const urlField = dialog.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-form-url-field]')
    const hiddenURLField = skill.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-url-field]')
    if (!urlField || !hiddenURLField) {
      return
    }
    hiddenURLField.value = urlField.value
    urlField.value = ''

    const parametersField = dialog.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-form-parameters-field]',
    )
    const hiddenParametersField = skill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-parameters-field]',
    )
    if (!parametersField || !hiddenParametersField) {
      return
    }
    hiddenParametersField.value = parametersField.value
    parametersField.value = ''

    const returnTypeField = dialog.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-form-return-type-field]',
    )
    const hiddenReturnTypeField = skill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-return-type-field]',
    )
    if (!returnTypeField || !hiddenReturnTypeField) {
      return
    }
    hiddenReturnTypeField.value = returnTypeField.value
    returnTypeField.value = ''
  }

  addSkill(event: MouseEvent) {
    if (!this.blankSkill || !this.skillsList || !this.skillsNewButton || !this.skillsBlankslate) {
      return
    }

    if (this.skillsList.childElementCount >= this.MAX_SKILLS) {
      this.skillsNewButton.hidden = true
      return
    }

    let dialog
    switch ((event.currentTarget as HTMLElement).id) {
      case 'skills-new-dialog-add':
        dialog = this.skillsNewButton
        break
      case 'skills-blankslate-dialog-add':
        dialog = this.skillsBlankslate
        break
      default:
        return
    }

    const newSkill = this.blankSkill.cloneNode(true) as HTMLDivElement

    this.saveSkillFromDialog(newSkill, dialog)

    newSkill.hidden = false

    this.skillsList.appendChild(newSkill)
    this.skillsList.hidden = false
    this.skillsNewButton.hidden = false
    this.skillsBlankslate.hidden = true

    if (this.skillsList.childElementCount >= this.MAX_SKILLS) {
      this.skillsNewButton.hidden = true
    } else {
      this.skillsNewButton.hidden = false
    }
  }

  removeSkill(event: Event) {
    if (!this.skillsList || !this.skillsBlankslate || !this.skillsNewButton) {
      return
    }

    for (const child of this.skillsList.children) {
      if (child.contains(event.target as HTMLElement)) {
        child.remove()
      }
    }

    // Hide when empty to prevent borders
    if (this.skillsList.children.length === 0) {
      this.skillsList.hidden = true
      this.skillsNewButton.hidden = true
      this.skillsBlankslate.hidden = false
    } else if (this.skillsList.children.length < this.MAX_SKILLS) {
      this.skillsNewButton.hidden = false
    }
  }

  openEditSkill(event: Event) {
    if (!this.skillsList) {
      return
    }

    const editingSkill = [...this.skillsList.children].find(child => child.contains(event.currentTarget as HTMLElement))
    if (!editingSkill) {
      return
    }

    const formName = editingSkill.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-form-name-field]')
    const name = editingSkill.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-name-field]')
    if (!formName || !name) {
      return
    }
    formName.value = name.value

    const formDescription = editingSkill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-form-description-field]',
    )
    const description = editingSkill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-description-field]',
    )
    if (!formDescription || !description) {
      return
    }
    formDescription.value = description.value

    const formURL = editingSkill.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-form-url-field]')
    const url = editingSkill.querySelector<HTMLInputElement>('[data-integration-agent-form=skill-url-field]')
    if (!formURL || !url) {
      return
    }
    formURL.value = url.value

    const formParameters = editingSkill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-form-parameters-field]',
    )
    const parameters = editingSkill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-parameters-field]',
    )
    if (!formParameters || !parameters) {
      return
    }
    formParameters.value = parameters.value

    const formReturnType = editingSkill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-form-return-type-field]',
    )
    const returnType = editingSkill.querySelector<HTMLInputElement>(
      '[data-integration-agent-form=skill-return-type-field]',
    )
    if (!formReturnType || !returnType) {
      return
    }
    formReturnType.value = returnType.value
  }

  saveEditSkill(event: Event) {
    if (!this.skillsList) {
      return
    }

    const editingSkill = [...this.skillsList.children].find(child => child.contains(event.target as HTMLElement))
    if (!editingSkill) {
      return
    }
    const editingDialog = editingSkill.querySelector('[data-integration-agent-form=skill-edit-dialog]')
    if (!editingDialog) {
      return
    }
    this.saveSkillFromDialog(editingSkill, editingDialog)
  }

  toggleOIDCFields() {
    if (!this.oidcFieldsToggle || !this.oidcFields) {
      return
    }

    if (this.oidcFieldsToggle.checked) {
      this.oidcFields.hidden = false
    } else {
      this.oidcFields.hidden = true
    }
  }
}
