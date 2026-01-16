/**
 * Codebuff Agent Type Definitions
 *
 * This file provides TypeScript type definitions for creating custom Codebuff agents.
 * Import these types in your agent files to get full type safety and IntelliSense.
 *
 * Usage in .agents/your-agent.ts:
 *   import { AgentDefinition, ToolName, ModelName } from './types/agent-definition'
 *
 *   const definition: AgentDefinition = {
 *     // ... your agent configuration with full type safety ...
 *   }
 *
 *   export default definition
 */

import type * as Tools from './tools'
import type { Message, ToolResultOutput, JsonObjectSchema } from './util-types'
type ToolName = Tools.ToolName

// ============================================================================
// Logger Interface
// ============================================================================

export interface Logger {
  debug: (data: any, msg?: string) => void
  info: (data: any, msg?: string) => void
  warn: (data: any, msg?: string) => void
  error: (data: any, msg?: string) => void
}

// ============================================================================
// Agent Definition and Utility Types
// ============================================================================

export interface AgentDefinition {
  /** Unique identifier for this agent. Must contain only lowercase letters, numbers, and hyphens, e.g. 'code-reviewer' */
  id: string

  /** Version string (if not provided, will default to '0.0.1' and be bumped on each publish) */
  version?: string

  /** Publisher ID for the agent. Must be provided if you want to publish the agent. */
  publisher?: string

  /** Human-readable name for the agent */
  displayName: string

  /** AI model to use for this agent. Can be any model in OpenRouter: https://openrouter.ai/models */
  model: ModelName

  /**
   * https://openrouter.ai/docs/use-cases/reasoning-tokens
   * One of `max_tokens` or `effort` is required.
   * If `exclude` is true, reasoning will be removed from the response. Default is false.
   */
  reasoningOptions?: {
    enabled?: boolean
    exclude?: boolean
  } & (
    | {
        max_tokens: number
      }
    | {
        effort: 'high' | 'medium' | 'low'
      }
  )

  // ============================================================================
  // Tools and Subagents
  // ============================================================================

  /** Tools this agent can use. */
  toolNames?: (ToolName | (string & {}))[]

  /** Other agents this agent can spawn, like 'codebuff/file-picker@0.0.1'.
   *
   * Use the fully qualified agent id from the agent store, including publisher and version: 'codebuff/file-picker@0.0.1'
   * (publisher and version are required!)
   *
   * Or, use the agent id from a local agent file in your .agents directory: 'file-picker'.
   */
  spawnableAgents?: string[]

  // ============================================================================
  // Input and Output
  // ============================================================================

  /** The input schema required to spawn the agent. Provide a prompt string and/or a params object or none.
   * 80% of the time you want just a prompt string with a description:
   * inputSchema: {
   *   prompt: { type: 'string', description: 'A description of what info would be helpful to the agent' }
   * }
   */
  inputSchema?: {
    prompt?: { type: 'string'; description?: string }
    params?: JsonObjectSchema
  }

  /** Whether to include conversation history from the parent agent in context.
   *
   * Defaults to false.
   * Use this if the agent needs to know all the previous messages in the conversation.
   */
  includeMessageHistory?: boolean

  /** How the agent should output a response to its parent (defaults to 'last_message')
   *
   * last_message: The last message from the agent, typically after using tools.
   *
   * all_messages: All messages from the agent, including tool calls and results.
   *
   * structured_output: Make the agent output a JSON object. Can be used with outputSchema or without if you want freeform json output.
   */
  outputMode?: 'last_message' | 'all_messages' | 'structured_output'

  /** JSON schema for structured output (when outputMode is 'structured_output') */
  outputSchema?: JsonObjectSchema

  // ============================================================================
  // Prompts
  // ============================================================================

  /** Prompt for when and why to spawn this agent. Include the main purpose and use cases.
   *
   * This field is key if the agent is intended to be spawned by other agents. */
  spawnerPrompt?: string

  /** Background information for the agent. Fairly optional. Prefer using instructionsPrompt for agent instructions. */
  systemPrompt?: string

  /** Instructions for the agent.
   *
   * IMPORTANT: Updating this prompt is the best way to shape the agent's behavior.
   * This prompt is inserted after each user input. */
  instructionsPrompt?: string

  /** Prompt inserted at each agent step.
   *
   * Powerful for changing the agent's behavior, but usually not necessary for smart models.
   * Prefer instructionsPrompt for most instructions. */
  stepPrompt?: string

  // ============================================================================
  // Handle Steps
  // ============================================================================

  /** Programmatically step the agent forward and run tools. */
  handleSteps?: (context: AgentStepContext) => Generator<
    ToolCall | 'STEP' | 'STEP_ALL',
    void,
    {
      agentState: AgentState
      toolResult: ToolResultOutput[] | undefined
      stepsComplete: boolean
    }
  >
}

// ============================================================================
// Supporting Types
// ============================================================================

export interface AgentState {
  agentId: string
  runId: string
  parentId: string | undefined

  /** The agent's conversation history: messages from the user and the assistant. */
  messageHistory: Message[]

  /** The last value set by the set_output tool. This is a plain object or undefined if not set. */
  output: Record<string, any> | undefined
}

/**
 * Context provided to handleSteps generator function
 */
export interface AgentStepContext {
  agentState: AgentState
  prompt?: string
  params?: Record<string, any>
  logger: Logger
}

/**
 * Tool call object for handleSteps generator
 */
export type ToolCall<T extends ToolName = ToolName> = {
  [K in T]: {
    toolName: K
    input: Tools.GetToolParams<K>
    includeToolCall?: boolean
  }
}[T]

// ============================================================================
// Available Models (see: https://openrouter.ai/models)
// ============================================================================

export type ModelName =
  | 'openai/gpt-5'
  | 'openai/gpt-5-chat'
  | 'openai/gpt-5-mini'
  | 'openai/gpt-5-nano'
  | 'anthropic/claude-4-sonnet-20250522'
  | 'anthropic/claude-opus-4.1'
  | 'anthropic/claude-sonnet-4'
  | 'google/gemini-2.5-pro'
  | 'google/gemini-2.5-flash'
  | (string & {})

export type { Tools }
