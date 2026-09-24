# Jupyter demo: local sample files ko inspect karein.
# Is file ko JupyterLab mein khol kar cells ke markers ke mutabiq run karein.

# %%
from pathlib import Path
import pandas as pd

DATA_DIR = Path('/home/jovyan/sample_data')
customers = pd.read_csv(DATA_DIR / 'customers.csv')
orders = pd.read_csv(DATA_DIR / 'orders.csv')

customers.head(), orders.head()

# %%
orders.groupby('customer_id', as_index=False)['amount'].sum()

# %%
# NiFi/S3 upload se pehle local data quality checks
assert customers['customer_id'].notna().all()
assert orders['order_id'].is_unique
assert (orders['amount'] >= 0).all()
print('local data quality checks passed')
