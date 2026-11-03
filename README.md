# Credit Risk Model

Home Credit Default Risk verisiyle temerrüt olasılığı modeli. Veri PostgreSQL'de
`raw -> stg -> mart` katmanlarından geçer, modeller `modeling.ipynb` içinde eğitilir.

## Kurulum

1. [Kaggle'daki Home Credit Default Risk](https://www.kaggle.com/c/home-credit-default-risk/data)
   yarışmasının CSV dosyalarını `home-credit-default-risk/` klasörüne koy.
2. Ortamı kur:

   ```bash
   cp .env.example .env
   python -m venv venv
   venv/bin/pip install -r requirements.txt
   docker compose up -d
   ```

3. Veri hattını çalıştır:

   ```bash
   venv/bin/python run_pipeline.py
   ```

   `raw` hazırsa yalnızca SQL adımları için `--skip-load` ekle.

4. Notebook'ları sırayla çalıştır: `modeling.ipynb`, `model_selection.ipynb`, `final_test.ipynb`.
   `final_test.ipynb`, `artifacts/test_result.json` varsa durur; test seti yalnızca bir kez kullanılır.

## Katmanlar

| Şema | İçerik |
|---|---|
| `raw` | CSV'lerin değiştirilmemiş hali |
| `stg` | Temizlik ve kaynak bazlı özetler |
| `mart` | Model özellik tabloları: `mart.features_application`, `mart.features_application_test` |
| `public` | Meta dosyalar: `columns_description`, `sample_submission` |

## Dosyalar

| Dosya | Görev |
|---|---|
| `run_pipeline.py` | Tüm veri hattını kurar |
| `load_to_postgres.py` | CSV'leri veritabanına yükler |
| `sql/` | Dönüşümler; ad sırasıyla çalışır ve tekrar çalıştırılabilir |
| `modeling.ipynb` | Baseline modeller (`fe_` özellikleri hariç) |
| `model_selection.ipynb` | CV, `organization_type`, hiperparametre, SHAP, kalibrasyon, eşik, fairness |
| `final_test.ipynb` | Tek seferlik test değerlendirmesi ve `application_test` tahminleri |
| `modeling_utils.py` | Notebook'ların ortak yardımcıları ve iş varsayımları |
| `artifacts/` | Kararlar, test sonucu ve grafikler |
| `data/split_ids.csv` | Train / validation / test atamaları |
| `data/submission.csv` | `application_test` tahminleri |
| `test.ipynb` | İlk veri keşfi |

## Sonuç

| Ölçüt | Değer |
|---|---|
| Test ROC-AUC | 0.7893 (%95 GA 0.7825-0.7962) |
| Test Gini | 0.5787 |
| 5-fold CV ROC-AUC | 0.7873 |
| Eşik | PD < 0.22 |
| Testte onay oranı | %92,0 |
| Onaylananda temerrüt | %5,9 (herkes onaylanırsa %8,1) |

Eşik, kredi tutarı başına %15 marj ve %50 kayıp varsayımıyla seçildi (`MARGIN`, `LGD`).
Bu değerler gerçek verilerle değiştirilmelidir. Veri yalnızca geçmişte onaylanmış kredileri
içerdiği için onay oranları gerçek başvuru akışını temsil etmez.

Test seti kullanıldı. Model değişirse yeni bir tarafsız ölçüm için yeni bir veri gerekir.
