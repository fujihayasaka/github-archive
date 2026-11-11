# Overriding Package to Repo mappings
Our `Matcher` code isn't always going to give 100% accuracy for mapping packages to github repos. To that end, we can override the package to repo mapping with a chatop:

`.dg package rubygems activerecord override rails/rails`

