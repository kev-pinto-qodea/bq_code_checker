import os  # Import the os module for directory operations
import sys  # Import sys for system-specific parameters and functions (e.g., sys.exit)
import argparse  # Import argparse for parsing command-line arguments

from google import genai
from google.genai import types
import time
import datetime  # For current date and time

"""
SQL Code Reviewer using Google GenAI.

This script automates the review of multiple SQL files within a specified directory
by leveraging Google's Generative AI (GenAI) models. It reads a system context
(e.g., coding standards, best practices) from `system_context.md` and generates
a QA report for each SQL file. Each report is saved as a markdown file with the
same base name as the SQL file (e.g., `my_script.sql` -> `my_script.md`).

The script is designed to be flexible, allowing users to specify the GCP project,
location, and the directory containing the SQL files via command-line arguments.

Usage:
    python ai_code_reviewer.py --sql_dir <path_to_sql_files> --project <gcp_project_id> --location <gcp_location>

Example:
    python ai_code_reviewer.py --sql_dir ./sql_scripts --project my-gcp-project --location us-central1
"""


def read_system_context() -> str:
    """
    Reads the system context from 'system_context.md'.

    This file typically contains the coding standards, best practices,
    or specific guidelines that the AI model should use during the review process.

    Returns:
        str: The content of the 'system_context.md' file.

    Raises:
        SystemExit: If the 'system_context.md' file is not found or
                    an unexpected error occurs during reading.
    """
    try:
        with open("./system_context.md", "r", encoding="utf-8") as file:
            print("--- Reading System Context ---")
            lines_list = file.read()
            return lines_list
    except FileNotFoundError:
        print(
            "Error: System Context file 'system_context.md' was not found in the current directory."
        )
        sys.exit(1)  # Exit if system context is missing, it's crucial for the review
    except Exception as e:
        print(f"An unexpected error occurred while reading system_context.md: {e}")
        sys.exit(1)


def read_prompt() -> str:
    """
    Reads the prompt from 'system_prompt.md'.

    The prompt is the specific instruction or query for a single turn of interaction

    Returns:
        str: The content of the 'system_prompt.md' file.

    Raises:
        SystemExit: If the 'system_prompt.md' file is not found or
                    an unexpected error occurs during reading.
    """
    try:
        with open("./system_prompt.md", "r", encoding="utf-8") as file:
            print("--- Reading System Prompt ---")
            lines_list = file.read()
            return lines_list
    except FileNotFoundError:
        print(
            "Error: System Prompt file 'system_prompt.md' was not found in the current directory."
        )
        sys.exit(1)  # Exit if system context is missing, it's crucial for the review
    except Exception as e:
        print(f"An unexpected error occurred while reading system_prompt.md: {e}")
        sys.exit(1)


def generate():
    """
    Main function to parse command-line arguments, initialize the GenAI client,
    and process all SQL files found in the specified directory.

    For each SQL file:
    1. Reads the SQL file content.
    2. Constructs a prompt by combining a predefined review request with the SQL code.
    3. Sends the prompt, along with the system context, to the Google GenAI model.
    4. Streams the AI's response and writes it to a new markdown file.

    Command-line Arguments:
        --project (str): The Google Cloud Project ID for Vertex AI.
                         Defaults to 'cts-sbx-1f2-upbeat-hermann' if not specified.
        --location (str): The Google Cloud region for Vertex AI.
                          Defaults to 'europe-west4' if not specified.
        --sql_dir (str): Required. The path to the directory containing
                         the SQL files (`.sql` extension) to be reviewed.

    Raises:
        SystemExit: If required arguments are missing, the specified SQL directory
                    does not exist or is not a directory, or critical errors occur
                    during the GenAI client initialization.
    """
    # 1. Define how the arguments should be parsed
    parser = argparse.ArgumentParser(
        description="A Pre-Commit hook to code Review SQL Code.", add_help=True
    )

    parser.add_argument(
        "--project",
        type=str,
        required=True,  # This argument is now required
        help='GCP Project ID for Vertex AI. (e.g., "your-project-id")',
    )

    parser.add_argument(
        "--location",
        type=str,
        required=True,  # This argument is now required
        help='GCP location for Vertex AI. (e.g., "us-central1")',
    )

    parser.add_argument(
        "--sql_dir",
        type=str,
        default="./sql",  # This argument is now required
        help="Path to the directory containing SQL files (.sql) to review.",
    )

    args = parser.parse_args()

    # Validate project and location (though defaults are provided, explicit check is good)
    if not args.project or not args.location:
        print("Error: Both --project and --location arguments are required.")
        sys.exit(1)

    # Validate the SQL directory
    if not os.path.isdir(args.sql_dir):
        print(f"Error: SQL directory '{args.sql_dir}' not found or is not a directory.")
        sys.exit(1)

    # Initialize GenAI client once outside the loop for efficiency
    print(
        f"--- Initializing GenAI Client for Project: {args.project}, Location: {args.location} ---"
    )
    try:
        client = genai.Client(
            vertexai=True,
            project=args.project,
            location=args.location,
        )
    except Exception as e:
        print(f"Error initializing GenAI client: {e}")
        print(
            "Please ensure your GCP project ID and location are correct and you have the necessary permissions."
        )
        sys.exit(1)

    si_text1 = read_system_context()  # System instruction text
    if not si_text1:
        print("Error: The system context is empty. Please check 'system_context.md'.")
        sys.exit(1)

    # Define model and generate content configuration once outside the loop
    model = "gemini-2.5-pro"  # Use the Pro model for better performance
    generate_content_config = types.GenerateContentConfig(
        temperature=0.1,  # Controls randomness. Lower values mean more deterministic output.
        top_p=1,  # Nucleus sampling. 1 means all tokens are considered.
        seed=0,  # For reproducibility of results.
        max_output_tokens=65535,  # Maximum number of tokens in the response.
        safety_settings=[  # Configure safety settings to allow more flexibility for code review
            types.SafetySetting(category="HARM_CATEGORY_HATE_SPEECH", threshold="OFF"),
            types.SafetySetting(
                category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="OFF"
            ),
            types.SafetySetting(
                category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="OFF"
            ),
            types.SafetySetting(category="HARM_CATEGORY_HARASSMENT", threshold="OFF"),
        ],
        system_instruction=[
            types.Part.from_text(text=si_text1)
        ],  # Pass system context as instruction
        thinking_config=types.ThinkingConfig(
            thinking_budget=-1,  # No budget limit for thinking steps
        ),
    )

    sql_files_found = False
    # Iterate through each file in the specified SQL directory
    for filename in os.listdir(args.sql_dir):
        # Check if the file has a .sql extension (case-insensitive)
        if filename.lower().endswith(".sql"):
            sql_files_found = True
            sql_file_path = os.path.join(args.sql_dir, filename)

            print(f"\n--- Processing SQL file: {filename} ---")
            stg_prompt_text = read_prompt()  # Read the prompt from the file
            if not stg_prompt_text:
                print("Error: The prompt text is empty. Please check 'system_prompt.md'.")
                sys.exit(1)

            prompt_text= stg_prompt_text.format(
                filename=filename
            )  # Format the prompt with the current filename

            try:
                # Read the content of the current SQL file
                with open(sql_file_path, "r", encoding="utf-8") as sql_file:
                    sql_file_content = sql_file.read()
            except Exception as e:
                print(f"Error reading {sql_file_path}: {e}")
                continue  # Skip to the next file if there's an error reading this one

            # Combine the prompt with the SQL file content for evaluation
            evaluation_text = prompt_text + sql_file_content

            # Create the content part for the GenAI model
            msg1_text1 = types.Part.from_text(text=evaluation_text)
            contents = [
                types.Content(role="user", parts=[msg1_text1]),
            ]

            # Construct the output QA filename using the SQL file's name
            base_filename = os.path.splitext(filename)[
                0
            ]  # Get filename without extension
            output_qa_filename = (
                os.path.join(args.sql_dir,f"{base_filename}.md")  # Create .md filename for the QA report
            )

            print(
                f"--- Generating QA Report for {filename} -> {output_qa_filename} ---"
            )

            try:
                # Open the output markdown file in write mode
                start_time = time.time()  # Record the start time
                with open(output_qa_filename, "w", encoding="utf-8") as md_file:
                    # Stream the content generation from the model
                    for chunk in client.models.generate_content_stream(
                        model=model,
                        contents=contents,
                        config=generate_content_config,
                    ):
                        # Write each chunk of the response to the Markdown file
                        md_file.write(chunk.text)
                end_time = time.time()  # Record the end time
                time_taken = end_time - start_time

                # Append the time taken and current date/time to the report
                with open(output_qa_filename, "a", encoding="utf-8") as md_file:
                    md_file.write(
                        f"\n\n---\n Report Generated at {datetime.datetime.now()} \n\n---\nTime taken for review: {time_taken:.2f} seconds\n"
                    )

                print(f"QA Report generated successfully in {output_qa_filename}")
            except Exception as e:
                print(f"Error writing QA report for {filename}: {e}")
                # Continue to the next file even if writing fails for one

    if not sql_files_found:
        print(f"No .sql files found in the directory: {args.sql_dir}")
    else:
        print("\n--- All SQL files processed. ---")


# Entry point for the script
if __name__ == "__main__":
    generate()
