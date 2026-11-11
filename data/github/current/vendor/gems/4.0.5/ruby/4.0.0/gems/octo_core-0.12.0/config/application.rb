# typed: true
# frozen_string_literal: true

# When we run `/bin/tapioca dsl` tapioca does not use the sorbet/tapioca/require.rb file.
# When we want to run a dsl compiler against files in the gems/ directory, we need this file to exist
# in order for tapioca to then read the config/environment.rb file.
# https://github.com/Shopify/tapioca/blob/1774124c0634f9f14e628b47bbeb61dae7b156d8/lib/tapioca/loaders/loader.rb#L36-L42
