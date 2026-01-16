/**
 * JSON Types
 */
export type JSONValue =
  | null
  | string
  | number
  | boolean
  | JSONObject
  | JSONArray

export type JSONObject = { [key: string]: JSONValue }
export type JSONArray = JSONValue[]

/**
 * JSON Schema definition (for prompt schema or output schema)
 */
export type JsonSchema = {
  type?:
    | 'object'
    | 'array'
    | 'string'
    | 'number'
    | 'boolean'
    | 'null'
    | 'integer'
  description?: string
  properties?: Record<string, JsonSchema | boolean>
  required?: string[]
  enum?: Array<string | number | boolean | null>
  [k: string]: unknown
}
export type JsonObjectSchema = JsonSchema & { type: 'object' }

/**
 * Content Part Types
 */
export interface TextPart {
  type: 'text'
  text: string
}

export interface ToolCallPart {
  type: 'tool-call'
  toolCallId: string
  toolName: string
  input: Record<string, unknown>
}

export interface ToolResultOutput {
  type: 'json' | 'media'
  value?: JSONValue
  data?: string
  mediaType?: string
}

export interface ToolResultPart {
  type: 'tool-result'
  toolCallId: string
  toolName: string
  output: ToolResultOutput[]
}

/**
 * Message Types
 */
export interface SystemMessage {
  role: 'system'
  content: string
}

export interface UserMessage {
  role: 'user'
  content: string | TextPart[]
}

export interface AssistantMessage {
  role: 'assistant'
  content: string | (TextPart | ToolCallPart)[]
}

export interface ToolMessage {
  role: 'tool'
  content: ToolResultPart
}

export type Message = SystemMessage | UserMessage | AssistantMessage | ToolMessage
