/**
 * Shared character counting functionality for text inputs with character limits.
 * Handles real-time character count updates, validation, and aria-live announcements.
 */
export class CharacterCounter {
    constructor(inputElement, characterLimitElement, characterLimitSrElement) {
        this.inputElement = inputElement;
        this.characterLimitElement = characterLimitElement;
        this.characterLimitSrElement = characterLimitSrElement;
        this.SCREEN_READER_DELAY = 500;
        this.announceTimeout = null;
        this.isInitialLoad = true;
    }
    /**
     * Initialize character counting by setting up event listener and initial count
     */
    initialize(signal) {
        this.inputElement.addEventListener('keyup', () => this.updateCharacterCount(), signal ? { signal } : undefined); // Keyup used over input for better screen reader support
        this.inputElement.addEventListener('paste', () => setTimeout(() => this.updateCharacterCount(), 50), // Gives the pasted content time to register
        signal ? { signal } : undefined);
        this.updateCharacterCount();
        this.isInitialLoad = false;
    }
    /**
     * Clean up any pending timeouts
     */
    cleanup() {
        if (this.announceTimeout) {
            clearTimeout(this.announceTimeout);
        }
    }
    /**
     * Pluralizes a word based on the count
     */
    pluralize(count, string) {
        return count === 1 ? string : `${string}s`;
    }
    /**
     * Update the character count display and validation state
     */
    updateCharacterCount() {
        if (!this.characterLimitElement)
            return;
        const maxLengthAttr = this.characterLimitElement.getAttribute('data-max-length');
        if (!maxLengthAttr)
            return;
        const maxLength = parseInt(maxLengthAttr, 10);
        const currentLength = this.inputElement.value.length;
        const charactersRemaining = maxLength - currentLength;
        let message = '';
        if (charactersRemaining >= 0) {
            const characterText = this.pluralize(charactersRemaining, 'character');
            message = `${charactersRemaining} ${characterText} remaining`;
            const textSpan = this.characterLimitElement.querySelector('.FormControl-caption-text');
            if (textSpan) {
                textSpan.textContent = message;
            }
            this.clearError();
        }
        else {
            const charactersOver = -charactersRemaining;
            const characterText = this.pluralize(charactersOver, 'character');
            message = `${charactersOver} ${characterText} over`;
            const textSpan = this.characterLimitElement.querySelector('.FormControl-caption-text');
            if (textSpan) {
                textSpan.textContent = message;
            }
            this.setError();
        }
        // We don't want this announced on initial load
        if (!this.isInitialLoad) {
            this.announceToScreenReader(message);
        }
    }
    /**
     * Announce character count to screen readers with debouncing
     */
    announceToScreenReader(message) {
        if (this.announceTimeout) {
            clearTimeout(this.announceTimeout);
        }
        this.announceTimeout = window.setTimeout(() => {
            if (this.characterLimitSrElement) {
                this.characterLimitSrElement.textContent = message;
            }
        }, this.SCREEN_READER_DELAY);
    }
    /**
     * Set error when character limit is exceeded
     */
    setError() {
        this.inputElement.setAttribute('invalid', 'true');
        this.inputElement.setAttribute('aria-invalid', 'true');
        this.characterLimitElement.classList.add('fgColor-danger');
        // Show danger icon
        const icon = this.characterLimitElement.querySelector('.FormControl-caption-icon');
        if (icon) {
            icon.removeAttribute('hidden');
        }
    }
    /**
     * Clear error when back under character limit
     */
    clearError() {
        this.inputElement.removeAttribute('invalid');
        this.inputElement.removeAttribute('aria-invalid');
        this.characterLimitElement.classList.remove('fgColor-danger');
        // Hide danger icon
        const icon = this.characterLimitElement.querySelector('.FormControl-caption-icon');
        if (icon) {
            icon.setAttribute('hidden', '');
        }
    }
}
