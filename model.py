from transformers import AutoImageProcessor, AutoModelForImageClassification
from PIL import Image
import requests
import torch
from io import BytesIO

model_id = "juppy44/plant-identification-2m-vit-b"

processor = AutoImageProcessor.from_pretrained(model_id)
model = AutoModelForImageClassification.from_pretrained(model_id)

# Define a standard browser User-Agent
headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

url = "https://upload.wikimedia.org/wikipedia/commons/a/a7/Pinus_sylvestris_-_K%C3%B6hler%E2%80%93s_Medizinal-Pflanzen-106_%28extracted%29.jpg"

# Pass the headers into the get request
response = requests.get(url, headers=headers)
response.raise_for_status()

image = Image.open(BytesIO(response.content)).convert("RGB")

inputs = processor(images=image, return_tensors="pt")
with torch.no_grad():
    logits = model(**inputs).logits

pred = logits.softmax(dim=-1)[0]
topk = torch.topk(pred, k=5)

for prob, idx in zip(topk.values, topk.indices):
    label = model.config.id2label[idx.item()]
    print(f"{label}: {prob.item():.4f}")

