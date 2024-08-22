import openai
import os
import pytest
from guardrails import Guard, settings

# OpenAI compatible Guardrails API Guard
openai.base_url = "http://127.0.0.1:8000/guards/chatbot/openai/v1/"

# the client requires this but we will use the key the server is already seeded with
# this does not need to be set as we will be proxying all our llm interaction through
# guardarils server
openai.api_key = os.getenv("OPENAI_API_KEY") or 'some key'

@pytest.mark.parametrize(
    "mock_llm_output, validation_output, validation_passed, error", [
        ("Paris is wonderful in the spring", "Paris is wonderful in the spring", False, True),
        ("Here is some info. You can find the answers there.","Here is some info. You can find the answers there.", True, False)
    ]
)
def test_guard_validation(mock_llm_output, validation_output, validation_passed, error):
    settings.use_server = True
    guard = Guard(name="chatbot")
    if error:
        with pytest.raises(Exception) as e:
            validation_outcome = guard.validate(mock_llm_output)
    else:
        validation_outcome = guard.validate(mock_llm_output)
        assert validation_outcome.validation_passed == validation_passed
        assert validation_outcome.validated_output == validation_output

@pytest.mark.parametrize(
    "message_content, output, validation_passed, error",[
        ("Tell me about Paris in a 10 word or less sentence", "Romantic, historic",False, True),
        ("Write a sentence using the word banana.", "banana", True, False)
    ]
)
def test_server_guard_llm_integration(message_content, output, validation_passed, error):
    settings.use_server = True
    guard = Guard(name="chatbot")
    messages =[
        {
            "role":"user",
            "content": message_content
        }
    ]
    if error:
        with pytest.raises(Exception):
            validation_outcome = guard(
                model="gpt-4o-mini",
                messages=messages,
                temperature=0.0,
            )
    else:
        validation_outcome = guard(
            model="gpt-4o-mini",
            messages=messages,
            temperature=0.0,
        )
        assert(output) in validation_outcome.validated_output
        assert(validation_outcome.validation_passed) is validation_passed

@pytest.mark.parametrize(
    "message_content, output, validation_passed, error",[
        ("Tell me about Paris in 5 words", "Romantic, historic",True, False),
        ("Write a sentence about a persons first day", "On her first day at the new job, she felt a mix of excitement and nerves as she stepped into the bustling office, ready to embrace the challenges ahead.", True, False)
    ]
)
def test_server_openai_llm_integration(message_content, output, validation_passed, error):
    messages =[
        {
            "role":"user",
            "content": message_content
        }
    ]
    if error:
        with pytest.raises(Exception) as e:
            completion = openai.chat.completions.create(
                model="gpt-4o-mini",
                messages=messages,
                temperature=0.0,
            )
        assert "Validation failed for field with errors: Found internal domains:" in str(e)
    else:
        completion = openai.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            temperature=0.0,
        )
        assert(output) in completion.choices[0].message.content
        assert(completion.guardrails['validation_passed']) is validation_passed

