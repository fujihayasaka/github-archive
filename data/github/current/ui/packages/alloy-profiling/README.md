# Alloy Profiling

This package contains a small server which allows you to profile the performance of an Alloy bundle within a browser.
The benefit to this approach is that Chrome DevTools can be used to profile the performance of the bundle for both Renders
and Resets. Chrome provides much finer grained detail compared to other profiling tools, such as VS Code.

## Running the Server

Run `npm start -w @github-ui/alloy-profiling` to start the server

## Build an Alloy Bundle

- `npm run webpack:alloy:prod` for a production bundle
- `npm run webpack:alloy` for a development bundle - this provides more detail, such as file and node_module names, but is not as close to production performance

Note: The server will automatically detect the bundle in `public/assets`, so you do not need to restart the server when you build a new bundle.

## Profiling a Bundle

- Visit <http://localhost:9101> in your browser
- Wait for the `Reset` and `Render` buttons to become enabled
- Click `Render` to render with the `args` present in the textarea. By default, this will be a `react-sandbox` app payload. You can change the args to match any other app/partial, though getting the right `payload` can be tricky. Even if you render with errors, you can still profile the performance of resets.
- Click `Reset` to call the `setup` function of the bundle. This simulates an isolation reset in Alloy.
- In DevTools, use the Performance tab to record a profile of renders and/or resets, which you can then manually analyze.
