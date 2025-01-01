import type {SessionResponse} from '../routes/session'

export function getSessionRoutePayload(): SessionResponse {
  return {
    pull: {
      id: 1,
      number: 1,
      title: 'Add README file',
      state: 'open',
      reviewable_state: 'draft',
      author: 'Copilot',
      comments: 1,
      created_at: '',
      updated_at: '',
      head_sha: '3462b1bd2493251aa3740ec2dcd6c1f74e3a0907',
      labels: [],
      repository_nwo: 'monalisa/smile',
      url: 'http://github.localhost/monalisa/smile/1',
    },
    repository: {
      ownerLogin: 'monalisa',
      name: 'smile',
      currentUserCanPush: true,
      id: 0,
      defaultBranch: '',
      createdAt: '',
      isFork: false,
      isEmpty: false,
      ownerAvatar: '',
      public: false,
      private: false,
      isOrgOwned: false,
    },
    logs: [
      {
        choices: [
          {
            finish_reason: 'tool_calls',
            delta: {
              content:
                "I'll help you create a README file for the repository. First, let me explore the contentto understand what needs to be documented.",
              role: 'assistant',
            },
          },
        ],
        created: 1742474126,
        id: '3398fe73-3f94-432d-aa78-52655b989493',
        model: 'Claude 3.5 Sonnet (Preview)',
        usage: {
          completion_tokens: 98,
          prompt_tokens: 2293,
          total_tokens: 2391,
        },
      },
      {
        choices: [
          {
            finish_reason: 'tool_calls',
            delta: {
              role: 'assistant',
              tool_calls: [
                {
                  function: {
                    arguments: '{"command":"cd /tmp/repo-5-1-1-5f08cd && ls -la"}',
                    name: 'bash',
                  },
                  id: 'tooluse_1pILVv7jQJOiGzH_OHpZHw',
                  type: 'function',
                  index: 0,
                },
              ],
            },
          },
        ],
        created: 1742474129,
        id: '9b6e0f28-4415-4a25-a77b-e22967562bb1',
        model: 'Claude 3.5 Sonnet (Preview)',
        usage: {
          completion_tokens: 72,
          prompt_tokens: 2518,
          total_tokens: 2590,
        },
      },
    ],
    sessions: [
      {
        id: '1d77c96b-52e9-41a6-9a60-4e27b3f5b72e',
        name: '',
        user_id: 123,
        agent_id: 456,
        state: 'in_progress',
        owner_id: 1,
        repo_id: 1,
        resource_type: 'issues',
        resource_id: 123,
        created_at: new Date(Date.now()).toISOString(),
        last_updated_at: new Date(Date.now()).toISOString(),
        completed_at: undefined,
        workflow_run_id: 14871321789,
        premium_requests: 0,
        log_entries: [
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content:
                    "I'll help you create a README file for the repository. First, let me explore the contentto understand what needs to be documented.",
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments: '{"command":"cd /tmp/repo-5-1-1-5f08cd && ls -la"}',
                        name: 'bash',
                      },
                      id: 'tooluse_1pILVv7jQJOiGzH_OHpZHw',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474126,
            id: '3398fe73-3f94-432d-aa78-52655b989493',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 98,
              prompt_tokens: 2293,
              total_tokens: 2391,
            },
          },
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments: '{"command":"cd /tmp/repo-5-1-1-5f08cd && cat File.md"}',
                        name: 'bash',
                      },
                      id: 'tooluse_ONJCj8-cTaCCQ8aDdrSLOQ',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474129,
            id: '9b6e0f28-4415-4a25-a77b-e22967562bb1',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 72,
              prompt_tokens: 2518,
              total_tokens: 2590,
            },
          },
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content: 'Let me check any git history or branches to understand more about the project:',
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments: '{"command":"cd /tmp/repo-5-1-1-5f08cd && git log --oneline"}',
                        name: 'bash',
                      },
                      id: 'tooluse_jI51bKl6Q1K9AiPfsKICDA',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474133,
            id: '5fe65c9c-8fa8-472c-a278-c011015dd1fc',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 89,
              prompt_tokens: 2603,
              total_tokens: 2692,
            },
          },
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content:
                    'This seems to be a simple repository with just a File.md containing "My Content". Let g an initial plan and reporting progress.',
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments:
                          '{"commitMessage":"Initialize plan for creating README","prDescription":"I will create a README.md file for this repository with minimal but essential documentation. Here\'s the plan:\n\n- [ ] Create a basic README.md with:\n  - [ ] Repository name and purpose\n  - [ ] Description of current content (File.md)\n  - [ ] Basic usage instructions\n  - [ ] Project structure\n- [ ] Test that the README.md is properly formatted\n- [ ] Verify README.md content accuracy\n- [ ] Ensure README.md follows best practices and is helpful for users\n\nFixes #1."}',
                        name: 'report_progress',
                      },
                      id: 'tooluse_5TLZmV7vRKma0yJe8_yLLA',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474141,
            id: 'b567b6b2-2426-49e1-ae0a-4f88d2c25589',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 225,
              prompt_tokens: 2721,
              total_tokens: 2946,
            },
          },
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content: 'Now let me create the README.md file with the essential information:',
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments:
                          '{"command":"create","file_text":"# File Content Repository\n\nA simple repository for managing file content.\n\n## Contents\n\nThis repository contains:\n\n- `File.md` - A markdown file containing basic content\n- `README.md` - This documentation file\n\n## Usage\n\nThe repository currently provides a basic markdown file (`File.md`) that can be viewed and edited. To view the content:\n\n```bash\ncat File.md\n```\n\n## Structure\n\n```\n.\n├── File.md    - Main content file\n└── README.md  - Documentation and usage instructions\n```\n\n## Contributing\n\nFeel free to submit pull requests to improve the content or documentation.","path":"/tmp/repo-5-1-1-5f08cd/README.md"}',
                        name: 'str_replace_editor',
                      },
                      id: 'tooluse_zX_3-DR0TiOGheV0kbtHcQ',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474150,
            id: '2ee8385c-d020-4768-bf64-baa896ad34ca',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 259,
              prompt_tokens: 2960,
              total_tokens: 3219,
            },
          },
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content: 'Now let me verify the README formatting and content by viewing it:',
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments: '{"command":"view","path":"/tmp/repo-5-1-1-5f08cd/README.md"}',
                        name: 'str_replace_editor',
                        result:
                          '# File Content Repository\n\nA simple repository for managing file content.\n\n## Contents\n\nThis repository contains:\n\n- `File.md` - A markdown file containing basic content\n- `README.md` - This documentation file\n\n## Usage\n\nThe repository currently provides a basic markdown file (`File.md`) that can be viewed and edited. To view the content:\n\n```bash\ncat File.md\n```\n\n## Structure\n\n```\n.\n├── File.md    - Main content file\n└── README.md  - Documentation and usage instructions\n```\n\n## Contributing\n\nFeel free to submit pull requests to improve the content or documentation.',
                      },
                      id: 'tooluse_6KzBxXYWSRKgfV4Gv3yk-A',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474153,
            id: '4ce2933a-d9a0-43d5-bf86-885fe6119803',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 105,
              prompt_tokens: 3254,
              total_tokens: 3359,
            },
          },
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content: 'Let me check if there are any linting issues or unwanted files:',
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments: '{"command":"cd /tmp/repo-5-1-1-5f08cd && git status --porcelain"}',
                        name: 'bash',
                      },
                      id: 'tooluse_N8UmBgAFTJaITJgeZOSPPw',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474156,
            id: '83be2b2f-8be7-489b-b45a-4f530929628b',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 90,
              prompt_tokens: 3502,
              total_tokens: 3592,
            },
          },
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content:
                    "The README.md looks good - it's properly formatted, contains all the essential informati kdown best practices. Let me update progress and commit the changes:",
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments:
                          '{"commitMessage":"Add README.md with repository documentation","prDescription":"I have created a clear and concise README.md for the repository. Here\'s what has been completed:\n\n- [x] Create a basic README.md with:\n  - [x] Repository name and purpose\n  - [x] Description of current content (File.md)\n  - [x] Basic usage instructions\n  - [x] Project structure\n- [x] Test that the README.md is properly formatted\n- [x] Verify README.md content accuracy\n- [x] Ensure README.md follows best practices and is helpful for users\n\nThe README.md includes:\n- Clear repository title and description\n- Contents listing all files\n- Usage instructions with example commands\n- Project structure visualization\n- Contributing section\n\nAll tasks have been completed. The README is minimal yet informative, providing all essential information for users.\n\nFixes #1."}',
                        name: 'report_progress',
                      },
                      id: 'tooluse_x1B9bfrRQxC6RsZECsfB8g',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474163,
            id: 'd87d59ad-2e91-482b-92dc-be09e0dbe0e8',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 296,
              prompt_tokens: 3608,
              total_tokens: 3904,
            },
          },
          {
            choices: [
              {
                finish_reason: 'stop',
                delta: {
                  content:
                    "I've completed all the requirements for creating a README file. The changes were minimal and focused on providing essential documentation:\n\n1. Created a README.md file with:\n   - Clear title and purpose\n   - List of contents\n   - Basic usage instructions\n   - Project structure visualization\n   - Contributing guidelines\n\n2. Verified the formatting and content accuracy\n3. Ensured the documentation follows markdown best practices\n4. Kept the changes minimal while providing all necessary information\n5. Made the content clear and helpful for users\n\nAll tasks have been completed and verified. Is there anything specific about the README that you'd like me to explain or modify?",
                  role: 'assistant',
                },
              },
            ],
            created: 1742474171,
            id: 'dfd64740-ce31-4b26-be80-97e9c6d7d71d',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 140,
              prompt_tokens: 3918,
              total_tokens: 4058,
            },
          },
          {
            choices: [
              {
                finish_reason: 'stop',
                delta: {
                  content:
                    'Add README with repository documentation\n\nCreated a clear README.md file that provides essential documentation for the repository. The README includes:\n\n- Repository name, purpose and description\n- List of repository contents and files\n- Usage instructions with example commands\n- Visual project structure representation\n- Basic contribution guidelines\n\nThe README was designed to be minimal yet informative, providing new users with all necessary information while keeping it concise and maintainable.\n\nFixes #1.',
                  role: 'assistant',
                },
              },
            ],
            created: 1742474174,
            id: 'c8a2aca6-1e7b-4ead-80b9-83cd2da1339c',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 97,
              prompt_tokens: 4171,
              total_tokens: 4268,
            },
          },
        ],
        error: null,
      },
    ],
    activeSessionId: '1d77c96b-52e9-41a6-9a60-4e27b3f5b72e',
    useMockData: true,
    pollingIntervals: {
      sessionsPollingInterval: 1000,
      logsPollingInterval: 1000,
    },
  }
}

export function getFailedSessionRoutePayload(): SessionResponse {
  return {
    pull: {
      id: 1,
      number: 1,
      title: 'Add README file',
      state: 'open',
      reviewable_state: 'draft',
      author: 'Copilot',
      comments: 1,
      created_at: '',
      updated_at: '',
      head_sha: '3462b1bd2493251aa3740ec2dcd6c1f74e3a0907',
      labels: [],
      repository_nwo: 'monalisa/smile',
      url: 'http://github.localhost/monalisa/smile/1',
    },
    repository: {
      ownerLogin: 'monalisa',
      name: 'smile',
      currentUserCanPush: true,
      id: 0,
      defaultBranch: '',
      createdAt: '',
      isFork: false,
      isEmpty: false,
      ownerAvatar: '',
      public: false,
      private: false,
      isOrgOwned: false,
    },
    logs: [
      {
        choices: [
          {
            finish_reason: 'tool_calls',
            delta: {
              content:
                "I'll help you create a README file for the repository. First, let me explore the contentto understand what needs to be documented.",
              role: 'assistant',
            },
          },
        ],
        created: 1742474126,
        id: '3398fe73-3f94-432d-aa78-52655b989493',
        model: 'Claude 3.5 Sonnet (Preview)',
        usage: {
          completion_tokens: 98,
          prompt_tokens: 2293,
          total_tokens: 2391,
        },
      },
      {
        choices: [
          {
            finish_reason: 'tool_calls',
            delta: {
              role: 'assistant',
              tool_calls: [
                {
                  function: {
                    arguments: '{"command":"cd /tmp/repo-5-1-1-5f08cd && ls -la"}',
                    name: 'bash',
                  },
                  id: 'tooluse_1pILVv7jQJOiGzH_OHpZHw',
                  type: 'function',
                  index: 0,
                },
              ],
            },
          },
        ],
        created: 1742474129,
        id: '9b6e0f28-4415-4a25-a77b-e22967562bb1',
        model: 'Claude 3.5 Sonnet (Preview)',
        usage: {
          completion_tokens: 72,
          prompt_tokens: 2518,
          total_tokens: 2590,
        },
      },
    ],
    sessions: [
      {
        id: '1d77c96b-52e9-41a6-9a60-4e27b3f5b72e',
        name: '',
        user_id: 123,
        agent_id: 456,
        state: 'failed',
        owner_id: 1,
        repo_id: 1,
        resource_type: 'issues',
        resource_id: 123,
        created_at: new Date(Date.now()).toISOString(),
        last_updated_at: new Date(Date.now()).toISOString(),
        completed_at: undefined,
        workflow_run_id: 14871321789,
        premium_requests: 2,
        log_entries: [
          {
            choices: [
              {
                finish_reason: 'tool_calls',
                delta: {
                  content:
                    "I'll help you create a README file for the repository. First, let me explore the contentto understand what needs to be documented.",
                  role: 'assistant',
                },
              },
              {
                finish_reason: 'tool_calls',
                delta: {
                  role: 'assistant',
                  tool_calls: [
                    {
                      function: {
                        arguments: '{"command":"cd /tmp/repo-5-1-1-5f08cd && ls -la"}',
                        name: 'bash',
                      },
                      id: 'tooluse_1pILVv7jQJOiGzH_OHpZHw',
                      type: 'function',
                      index: 0,
                    },
                  ],
                },
              },
            ],
            created: 1742474126,
            id: '3398fe73-3f94-432d-aa78-52655b989493',
            model: 'Claude 3.5 Sonnet (Preview)',
            usage: {
              completion_tokens: 98,
              prompt_tokens: 2293,
              total_tokens: 2391,
            },
          },
        ],
        error: {
          message: 'Copilot has encountered an internal error. Request Id: F500:1BA5F:C65E20:126350B:680D1091',
        },
      },
    ],
    activeSessionId: '1d77c96b-52e9-41a6-9a60-4e27b3f5b72e',
    useMockData: true,
    pollingIntervals: {
      sessionsPollingInterval: 1000,
      logsPollingInterval: 1000,
    },
  }
}
