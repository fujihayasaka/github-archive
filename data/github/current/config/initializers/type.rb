# frozen_string_literal: true

require "color_mode_type"
require "user_theme_type"
require "utc_timestamp"
require "uuid_type"
ActiveRecord::Type.register(:color_mode_type, ColorModeType)
ActiveRecord::Type.register(:user_theme_type, UserThemeType)
ActiveRecord::Type.register(:utc_timestamp, UtcTimestamp)
ActiveRecord::Type.register(:uuid_type, UUIDType)
