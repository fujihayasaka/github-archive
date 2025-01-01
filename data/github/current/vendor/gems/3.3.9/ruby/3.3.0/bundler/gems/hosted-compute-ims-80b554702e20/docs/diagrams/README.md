# Diagrams

The diagrams in this folder are written using [D2](https://d2lang.com/) diagram scripting language.
D2 uses files with the `.d2` extension to store the source code of diagrams. The D2 CLI tool is used to compile `.svg`, `.png` or `.pdf` files from these `.d2` files.

Check out the [D2 Tour Intro](https://d2lang.com/tour/intro/) to learn how to build D2 diagrams. 

## Build svg from d2 files

Use `script/diagrams` script to build all diagrams in `docs/diagrams` folder. SVG files will be saved in the `docs/assets` folder.

## Define layout engine and theme for diagram

Use the following statement at the beginning of `.d2` file to define the layout engine, theme, and sketch mode:
```
vars: {
  d2-config: {
    theme-id: 0
    layout-engine: elk
    sketch: true
  }
}
```

- Available layout engines: https://d2lang.com/tour/layouts
- Available themes: https://d2lang.com/tour/themes

## Development

### Use D2 CLI in watch mode

This command will open a page in your default browser which will contain the rendered diagram.  
This diagram will automatically be re-rendered on every file save.

```
d2 -w <d2_file>
```

For more information about CLI watch mode see  - [Using the CLI watch mode](https://d2lang.com/tour/intro/#using-the-cli-watch-mode).

### Use VSCode extension

The official D2 VSCode extension is already pre-installed in the Codespaces environment.
Use the Command Palette commands to render a preview or configure the render layout and theme:

<img width="613" alt="Screenshot 2023-10-12 at 23 55 36" src="https://github.com/github/hosted-compute-ims/assets/16715858/68921f72-2fe8-4f7e-b6c5-a84f0c15b412">

### Use D2 Playground

D2 provides an [online playground](https://play.d2lang.com/) with syntax highlighting and hot reloading. It provides a good UX and allows you to compare diagram renders using different layout engines and themes.
