import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error as MSE
from sklearn.ensemble import RandomForestRegressor
import pickle
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, MinMaxScaler
from sklearn.pipeline import Pipeline
import ray
import boto3
from io import BytesIO

ray.init()

@ray.remote
def read_csv_from_s3(bucket_name, file_key):
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=bucket_name, Key=file_key)
    data = response['Body'].read()
    df = pd.read_csv(BytesIO(data))
    return df

@ray.remote
def write_model_to_s3(bucket_name, file_key, model):
    s3 = boto3.client('s3')
    buffer = BytesIO()
    pickle.dump(model, buffer)
    s3.put_object(Bucket=bucket_name, Body=buffer.getvalue(), Key=file_key)

def cleaning(df):
    df.rename(columns={'swimming-pool': 'swimming_pool', 'state-building': 'state_building', 'land-surface': 'land_surface'}, inplace=True)
    df.drop(df[df['state_building'] == "0"].index, inplace=True)
    df['state_building'] = df['state_building'].astype(str)
    df.duplicated()
    df.fillna(0, inplace=True)
    df.drop(df[df['locality'] == 0].index, inplace=True)
    df.drop(columns=['type-transaction', 'url', 'area_terrace', 'area-garden', 'n-facades'], inplace=True)
    return df

def model(df):
    df.dropna(inplace=True)
    X = df.drop(['price'], axis=1)
    y = df['price']
    trans_1 = ColumnTransformer([
        ('ohe_trans', OneHotEncoder(sparse=False, handle_unknown='ignore'), [0, 1, 2, 12])
    ], remainder='passthrough')
    trans_2 = ColumnTransformer([
        ('scale', MinMaxScaler(), slice(0, len(X)+1))
    ], remainder='passthrough')
    trans_3 = RandomForestRegressor(random_state=3)
    pipeline = Pipeline(steps=[('trans_1', trans_1), ('trans_2', trans_2), ('trans_3', trans_3)])
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    pipeline.fit(X_train, y_train)
    pred = pipeline.predict(X_test)
    rmse = np.sqrt(MSE(y_test, pred))
    return pipeline

def main():
    input_bucket_name = "nachtje-terraform-demo"                    # your bucket name  
    input_file_key = "data/dataset_immo.csv"                        # path in your bucket to your .csv file  
    output_bucket_name = "nachtje-terraform-demo"                   # your bucket name
    output_file_key = "model/nachtje-model.pickle"                  # path to your model output. Change after 

    df_future = read_csv_from_s3.remote(input_bucket_name, input_file_key)
    df = ray.get(df_future)
    cleaned_df = cleaning(df)
    trained_model = model(cleaned_df)
    ray.get(write_model_to_s3.remote(output_bucket_name, output_file_key, trained_model))


if __name__ == "__main__":
    main()
