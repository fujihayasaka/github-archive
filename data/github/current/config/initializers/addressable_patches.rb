# frozen_string_literal: true

require "addressable_monkey_patches"
AddressableMonkeyPatches.patch!(target: Addressable::URI)
