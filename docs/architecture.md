# Setmode System Architecture

Setmode is a structured thinking engine for strategists, creators, and connectors. It transforms raw ideas into scalable outputs using a modular system.

## Stack Overview

| Layer          | Tool        | Role                                  |
|----------------|-------------|---------------------------------------|
| Frontend (UI)  | WeWeb AI    | Dynamic interface for user interaction |
| Database       | Supabase    | Data, auth, vector store              |
| Automation     | n8n         | GPT logic + workflow automation       |
| Voice Input    | Whisper API | STT → GPT ingestion                   |
| Output         | ElevenLabs  | Voice feedback (TTS)                  |

## Core Modes

- **Clarify**: Turn raw input into structured insight  
- **Codify**: Convert insights into reusable formats  
- **Amplify**: Personalize + distribute across channels

## Supabase Tables

- `insights`, `insight_versions`, `insight_relations`
- `prompt_templates`, `persona_profiles`
- `users`, `workspaces`, `vector_store`

## n8n Workflows

- `voice-to-insight`
- `prompt-chain-output`
- `auto-distribute-to-buffer`

## Prompt Templates

- `clarify.md`
- `codify.md`
- `amplify.md`
