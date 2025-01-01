export interface HiddenInputsProps {
  emailDomains: string
  isCameraRequired: string
  isDistanceLimitOverridden: string
  isNewSchool: string
  isTwoFactorRequired: string
  isUserTooFarFromSchool: string
  selectedSchoolId: string
}

export function HiddenInputs({
  emailDomains,
  isCameraRequired,
  isDistanceLimitOverridden,
  isNewSchool,
  isTwoFactorRequired,
  isUserTooFarFromSchool,
  selectedSchoolId,
}: HiddenInputsProps) {
  return (
    <div>
      <input
        type="hidden"
        name="dev_pack_form[camera_required]"
        data-testid="camera-required"
        value={isCameraRequired}
      />
      <input type="hidden" name="dev_pack_form[email_domains]" data-testid="email-domains" value={emailDomains} />
      <input type="hidden" name="dev_pack_form[new_school]" data-testid="new-school" value={isNewSchool} />
      <input
        type="hidden"
        name="dev_pack_form[override_distance_limit]"
        data-testid="distance-limit-overridden"
        value={isDistanceLimitOverridden}
      />
      <input
        type="hidden"
        name="dev_pack_form[selected_school_id]"
        data-testid="selected-school-id"
        value={selectedSchoolId}
      />
      <input
        type="hidden"
        name="dev_pack_form[two_factor_required]"
        data-testid="two-factor-required"
        value={isTwoFactorRequired}
      />
      <input
        type="hidden"
        name="dev_pack_form[user_too_far_from_school]"
        data-testid="user-too-far-from-school"
        value={isUserTooFarFromSchool}
      />
    </div>
  )
}
