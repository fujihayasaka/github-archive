# Migration Step: Update Controllers

- **You must always read in and follow the referenced diff file (`update_controllers.diff`) as your primary source of truth for code structure, naming, and placement.**
- For every migration, before making any changes:
  - **Read the entire referenced diff file.**
  - Use the diff as your step-by-step guide. **Do not deviate from the structure, naming, or placement shown in the diff.**
  - All code changes, including imports, array structure, and registration, must match the diff as closely as possible.
  - Attempt to match the routes in `path-to-app` to the correct controller actions in `path-to-controller`. If unsure, refer to the file `config/routes.rb` to determine the actions.
  - Confirm with the user if the identified actions are correct.
  - Suggest a feature flag name to use.
  - Ensure feature flag method is added after the `private` statement in the controller and that it return the value of `check_app_type_header` if it is not `nil`.
  - Ensure the payload classes are created and used by the actions.
  - Run the command `rubocop <path-to-controller> --autocorrect-all` and attempt to fix any errors that occur.
  - **Do not add extra code, comments, or examples.**
  - Before making any changes, summarize what changes you will make, referencing the diff. If your summary includes any new files not shown in the diff, it is incorrect—try again.
- **Every time you perform this migration step, the referenced diff must be read and used as the main driver for your changes.**
