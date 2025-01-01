module VendorRegex
  # This regular expression is taken from linguist
  # https://github.com/github-linguist/linguist/blob/5a0c74277548122267d84283910abd5e0b89380e/lib/linguist/vendor.yml
  #
  # We only care about manifests so a lot of things are deleted, and it's
  # reorganized to be more performant. There are probably many more entries that
  # could be safely removed if someone wants to take the time to go through
  # carefully and understand what can contain manifests.
  Regex = %r{
    ^[Dd]ependencies/
    | (3rd|[Tt]hird)[-_]?[Pp]arty/

    # Xcode
    ### these can be part of a directory name
    | \.xctemplate/
    | \.imageset/

    # Debian packaging
    | ^debian/
    # C deps
    | ^deps/

    # Everything below here is anchored by (^|/)
    | (^|/) (
      cache/
      | dist/

      # linters
      | cpplint\.py

      # node dependencies
      | node_modules/

      # yarn 2
      | \.yarn/releases/
      | \.yarn/plugins/
      | \.yarn/sdks/
      | \.yarn/versions/
      | \.yarn/unplugged/

      # bower components
      | bower_components/

      # erlang bundles
      | erlang\.mk

      # go dependencies
      | godeps/_workspace/

      # go fixtures
      | testdata/

      # vendored dependencies
      | vendors?/
      | [ee]xtern(als?)?/
      | [vv]+endor/

      # bootstrap datepicker
      | bootstrap-datepicker/

      # sublime text workspace files
      | \.sublime-project
      | \.sublime-workspace

      # vs code workspace files
      | \.vscode/


      # wys editors
      | tiny_mce/(langs|plugins|themes|utils)

      # ace editor
      | ace-builds/

      # mathjax
      | mathjax/

      # codemirror
      | [cc]ode[mm]irror/(\d+\.\d+/)?(lib|mode|theme|addon|keymap|demo)

      ## python ##

      # sphinx
      | docs?/_?(build|themes?|templates?|static)/

      # django
      | admin_media/
      | env/

      ## obj-c ##


      # carthage
      | carthage/

      # sparkle
      | sparkle/

      # crashlytics
      | crashlytics\.framework/

      # fabric
      | fabric\.framework/

      # buddybuild
      | buddybuildsdk\.framework/

      # realm
      | realm\.framework

      # realmswift
      | realmswift\.framework

      ## groovy ##

      # gradle
      | gradle/wrapper/

      ## java ##

      # maven
      | \.mvn/wrapper/

      ## .net ##

      # nuget
      | [pp]ackages\/.+\.\d+\/

      # extjs
      | extjs/\.sencha/
      | extjs/docs/
      | extjs/builds/
      | extjs/cmd/
      | extjs/examples/
      | extjs/locale/
      | extjs/packages/
      | extjs/plugins/
      | extjs/resources/
      | extjs/src/
      | extjs/welcome/

      # test fixtures
      | [tt]ests?/fixtures/
      | [ss]pecs?/fixtures/

      # r packages
      | inst/extdata/

      # puphpet
      | puphpet/

      # android google apis
      | \.google_apis/

      # obsidian.md settings
      | \.obsidian/
    )
  }x
end
