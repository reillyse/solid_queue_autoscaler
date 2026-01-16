/**
 * Union type of all available tool names
 */
export type ToolName =
  | 'add_message'
  | 'code_search'
  | 'end_turn'
  | 'find_files'
  | 'lookup_agent_info'
  | 'read_docs'
  | 'read_files'
  | 'run_file_change_hooks'
  | 'run_terminal_command'
  | 'set_messages'
  | 'set_output'
  | 'spawn_agents'
  | 'str_replace'
  | 'think_deeply'
  | 'web_search'
  | 'write_file'

/**
 * Map of tool names to their parameter types
 */
export interface ToolParamsMap {
  add_message: AddMessageParams
  code_search: CodeSearchParams
  end_turn: EndTurnParams
  find_files: FindFilesParams
  lookup_agent_info: LookupAgentInfoParams
  read_docs: ReadDocsParams
  read_files: ReadFilesParams
  run_file_change_hooks: RunFileChangeHooksParams
  run_terminal_command: RunTerminalCommandParams
  set_messages: SetMessagesParams
  set_output: SetOutputParams
  spawn_agents: SpawnAgentsParams
  str_replace: StrReplaceParams
  think_deeply: ThinkDeeplyParams
  web_search: WebSearchParams
  write_file: WriteFileParams
}

export interface AddMessageParams {
  role: 'user' | 'assistant'
  content: string
}

export interface CodeSearchParams {
  pattern: string
  flags?: string
  cwd?: string
  maxResults?: number
}

export interface EndTurnParams {}

export interface FindFilesParams {
  prompt: string
}

export interface LookupAgentInfoParams {
  agentId: string
}

export interface ReadDocsParams {
  libraryTitle: string
  topic: string
  max_tokens?: number
}

export interface ReadFilesParams {
  paths: string[]
}

export interface RunFileChangeHooksParams {
  files: string[]
}

export interface RunTerminalCommandParams {
  command: string
  process_type?: 'SYNC' | 'BACKGROUND'
  cwd?: string
  timeout_seconds?: number
}

export interface SetMessagesParams {
  messages: any
}

export interface SetOutputParams {}

export interface SpawnAgentsParams {
  agents: {
    agent_type: string
    prompt?: string
    params?: Record<string, any>
  }[]
}

export interface StrReplaceParams {
  path: string
  replacements: {
    old: string
    new: string
    allowMultiple?: boolean
  }[]
}

export interface ThinkDeeplyParams {
  thought: string
}

export interface WebSearchParams {
  query: string
  depth?: 'standard' | 'deep'
}

export interface WriteFileParams {
  path: string
  instructions: string
  content: string
}

export type GetToolParams<T extends ToolName> = ToolParamsMap[T]
