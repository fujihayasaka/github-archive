# Scripts directory

## Scripts you probably will not run (directly)

Many of the scripts exist to help out other scripts, or to support things like CI. These are listed in alphabetical order. In addition, all scripts in the helpers directory fall into this category although they are not explicitly listed here.

### script/resolve-dependencies

Run only by GitHub's internal CI before builds. It installs the necessary Go modules so we don't vendor our dependencies or restore modules inside the build container.

