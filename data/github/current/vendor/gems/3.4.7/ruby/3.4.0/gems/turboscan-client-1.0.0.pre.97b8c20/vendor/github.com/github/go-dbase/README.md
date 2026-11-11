# go-dbase

A database helper to load Skeema configuration for services written in Go

## Usage

When you are building a Go service which uses a MySQL database, you will find it is common to use Skeema to manage the database schema.
In this case you will already have a `schemas/.skeema` file which describes each of the database environments.

Instead of duplicating the configuration, you can leverage this Skeema configuration file to initialize a GORM database connection with this package.

Example:

```go
package main

import (
  dbase "github.com/github/go-dbase"
  "github.com/jinzhu/gorm"
)

func main() {
  var db *gorm.DB
  db, err := dbase.Open("schemas/.skeema", "development")
  if err != nil {
      fmt.Fprint(os.Stderr, err)
      os.Exit(1)
  }

  // Do stuff with db ...
}
```

## Contributing

This repository is owned by [@dev-frameworks](https://github.com/github/dev-frameworks/), and we welcome contributions! To learn more about developing and making updates to this repo, please see [the contributing guide](./CONTRIBUTING.md).
