/**
 * Shared character counting functionality for text inputs with character limits.
 * Handles real-time character count updates, validation, and aria-live announcements.
 */
export declare class CharacterCounter {
    private inputElement;
    private characterLimitElement;
    private characterLimitSrElement;
    private SCREEN_READER_DELAY;
    private announceTimeout;
    private isInitialLoad;
    constructor(inputElement: HTMLInputElement | HTMLTextAreaElement, characterLimitElement: HTMLElement, characterLimitSrElement: HTMLElement);
    /**
     * Initialize character counting by setting up event listener and initial count
     */
    initialize(signal?: AbortSignal): void;
    /**
     * Clean up any pending timeouts
     */
    cleanup(): void;
    /**
     * Pluralizes a word based on the count
     */
    private pluralize;
    /**
     * Update the character count display and validation state
     */
    private updateCharacterCount;
    /**
     * Announce character count to screen readers with debouncing
     */
    private announceToScreenReader;
    /**
     * Set error when character limit is exceeded
     */
    private setError;
    /**
     * Clear error when back under character limit
     */
    private clearError;
}
