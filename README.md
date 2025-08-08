Setmode

Setmode is a system built to help strategists, creators, and connectors turn ideas into action. It’s designed to make it easier to think clearly, build structured content, and share it at scale.

⸻

What’s Inside

This project is organized into the following folders:
	•	prompts – Templates that help the AI generate content. Split into three types: Clarify, Codify, and Amplify.
	•	schema – Supabase SQL file that defines the structure of the database, including rules and data types.
	•	workflows – Automation workflows built in n8n that connect all the parts and run the logic.
	•	docs – Notes, system designs, and other documentation.
	•	public – Files that are meant to be shared or published publicly.
	•	README.md – This file. It explains how the system is structured and what it does.

⸻

Tech Stack
	•	WeWeb – Visual front end that users interact with.
	•	Supabase – Manages data, user accounts, and permissions.
	•	n8n – Runs automation and connects all the tools together.
	•	OpenAI – Handles intelligence and voice:
	•	GPT-4o for reasoning and generation
	•	Whisper for speech-to-text
	•	TTS (text-to-speech) for voice responses using GPT voice

⸻

Getting Started

To run this system on your own:
	1.	Install Supabase CLI.
	2.	Use the setmode-schema.sql file to set up the database.
	3.	Import the n8n workflows into your n8n setup.
	4.	Link with WeWeb for the front end.
	5.	Add OpenAI API keys for voice and GPT functionality.

⸻

Security Note

There are no personal credentials or secrets in this repo. You’re safe to explore or clone.

⸻

Contributing

Feel free to make suggestions or open a pull request. If you’re planning to build something significant on top of this, please check in first so we stay aligned.

