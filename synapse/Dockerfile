FROM matrixdotorg/synapse:latest

# Install any extra requirements
COPY requirements.txt /requirements.txt
RUN if [ -s /requirements.txt ]; then         pip install --no-cache-dir -r /requirements.txt;     fi
