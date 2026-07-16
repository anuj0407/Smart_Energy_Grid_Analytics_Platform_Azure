"""
Simulates a live smart meter by replaying rows from household_power_consumption.txt
at timed intervals, publishing each as a JSON event to Azure Event Hubs.

This stands in for a real meter feed per the project's documented design:
there is no live household meter, so this script is the streaming source of truth.
"""

import csv
import io
import json
import time
import random
import zipfile
from datetime import datetime
from azure.eventhub import EventHubProducerClient, EventData

# --- Configuration ---
CONNECTION_STR = "PRIMARY CONNECTION STRING"
EVENT_HUB_NAME = "meter-readings"
SOURCE_ZIP = "../../datasets/individual_household_electric_power_consumption.zip"  # relative path from pyspark/extraction/
SOURCE_FILE_IN_ZIP = "household_power_consumption.txt"  # filename INSIDE the zip
SEND_INTERVAL_SECONDS = 2          # delay between simulated readings
ANOMALY_INJECTION_RATE = 0.02      
START_ROW_OFFSET = 2_000_000       

def build_event(row: dict, inject_anomaly: bool) -> dict:
    #Shape a raw file row into the same 9-field structure as the batch source.
    voltage = row["Voltage"]
    if voltage != "?" and inject_anomaly:
        # Push voltage outside the documented 220-256V plausible range
        voltage = str(round(random.choice([
            random.uniform(180, 215),   
            random.uniform(260, 290),   
        ]), 2))

    return {
        "Date": row["Date"],
        "Time": row["Time"],
        "Global_active_power": row["Global_active_power"],
        "Global_reactive_power": row["Global_reactive_power"],
        "Voltage": voltage,
        "Global_intensity": row["Global_intensity"],
        "Sub_metering_1": row["Sub_metering_1"],
        "Sub_metering_2": row["Sub_metering_2"],
        "Sub_metering_3": row["Sub_metering_3"],
        "sent_at": datetime.utcnow().isoformat(),
    }


def run_producer():
    producer = EventHubProducerClient.from_connection_string(
        conn_str=CONNECTION_STR, eventhub_name=EVENT_HUB_NAME
    )

    with zipfile.ZipFile(SOURCE_ZIP, "r") as zf:
        with zf.open(SOURCE_FILE_IN_ZIP) as raw_f:
            f = io.TextIOWrapper(raw_f, encoding="utf-8")
            reader = csv.DictReader(f, delimiter=";")
            for i, row in enumerate(reader):
                if i < START_ROW_OFFSET:
                    continue  # skip ahead so streaming uses a different slice than batch demoed on

                inject_anomaly = random.random() < ANOMALY_INJECTION_RATE
                event = build_event(row, inject_anomaly)

                batch = producer.create_batch()
                batch.add(EventData(json.dumps(event)))
                producer.send_batch(batch)

                print(f"Sent: {event['Date']} {event['Time']} | Voltage={event['Voltage']}"
                      f"{'  <-- ANOMALY INJECTED' if inject_anomaly else ''}")

                time.sleep(SEND_INTERVAL_SECONDS)

    producer.close()


if __name__ == "__main__":
    run_producer()
