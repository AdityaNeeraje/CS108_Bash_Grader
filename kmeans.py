# from sklearn.cluster import KMeans
# from sklearn.neighbors import KNeighborsRegressor
import pandas as pd
import numpy as np
from sklearn.cluster import DBSCAN
from sklearn.preprocessing import StandardScaler
from matplotlib import pyplot as plt
# import numpy as np

data=pd.read_csv("main.csv")
data.replace(to_replace=r'^a*$', value='0', regex=True, inplace=True)
data["Total"]=(data.iloc[:,2:].astype('float64')).sum(axis=1)
x=data['Total'].values.reshape(-1,1)
x=sorted(x)
# x=np.ones((len(data),1))
# y=data['Total']
# # kmeans=KMeans(n_clusters=6)
# # kmeans.fit(list(zip(x,y)))
# knn=KNeighborsRegressor(n_neighbors=6)
# knn.fit(x,y)

# plt.scatter(x, y, c=knn.predict(x), cmap='rainbow')
# plt.show()


dbscan = DBSCAN(eps=0.1, min_samples=5)

# Fit the model
clusters = dbscan.fit_predict(x)
print("Number of clusters found:", len(set(clusters)) - (1 if -1 in clusters else 0))
print("Noise points:", list(clusters).count(-1))

plt.scatter(np.arange(len(x)), x, c=clusters, cmap='rainbow')
plt.show()