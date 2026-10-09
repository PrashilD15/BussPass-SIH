import os
from google.adk import Agent
from google.adk.runner import Runner

agent = Agent(
    name="msrtc_agent",
    model="gemini-3.6-flash",
    instruction="You are an MSRTC Helpdesk Officer."
)

print(dir(agent))
