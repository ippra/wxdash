# WxDash Repository 

This repository archives and documents the data and `R code` necessary to produce the [Extreme Weather and Society Dashboard (WxDash)](https://crcm.shinyapps.io/WxDash/). 

<a href = "https://crcm.shinyapps.io/WxDash/">
 <img src="https://raw.githubusercontent.com/oucrcm/wxdash/master/example_dash.png" width="500" alt="chart">
</a>

WxDash is currently maintained by researchers at the University of Oklahoma's [Institute for Public Policy Research and Analysis](https://ou.edu/ippra). WxDash uses data from a yearly survey of US adults to systematically measure, map, and track forecast and warning reception, comprehension, and response in counties and County Warning Areas across the country. Survey data are available in the [Extreme Weather and Society Survey Dataverse](https://dataverse.harvard.edu/dataverse/wxsurvey).

This README provides a short overview of each step in the project. As the steps below indicate, the code makes use of data and GIS files from multiple sources. Users who wish to replicate this code will have to begin by downloading these files. The code assumes that users are storing them in a local folder called `Downloads`. [Here](https://www.dropbox.com/sh/g6f0kyq5rlufq02/AAD4u06hr5RqqRXH_HCCurCja?dl=0) is a pre-made folder that contains all of these files. Users can find and download the original files here:

Data files:

- [Storm event data files (22 files); StormEvents_details*.csv](https://www1.ncdc.noaa.gov/pub/data/swdi/stormevents/csvfiles/)
- [USDM data files (22 files); dm_export*.csv](https://droughtmonitor.unl.edu/Data/DataDownload/ComprehensiveStatistics.aspx)
- [CDC SVI data file (1 file); SVI_2020_US_county.csv](https://www.atsdr.cdc.gov/placeandhealth/svi/data_documentation_download.html)
- [Wx Survey data files (11 files); WX*.csv & TC*.csv](https://dataverse.harvard.edu/dataverse/wxsurvey)
- [USPS ZIP Code data file (1 file); ZIP_COUNTY_032020.xlsx](https://www.huduser.gov/portal/datasets/usps_crosswalk.html)

GIS files:

- [NWS County Shapefile (c_03mr20)](https://www.weather.gov/gis/Counties)
- [NWS CWA Shapefile (w_03mr20)](https://www.weather.gov/gis/CWABounds)

Steps to produce estimates:

1.	**Create base storm event dataset**. This step calculates the frequency of storm events by CWA and county.
        
    - Run: 1_create_base_storm_event dataset
    - Outputs: 
        - base_cwa_storm_data.csv
        - base_county_storm_data.csv

2.	**Create base census dataset**. This step calculates Census margins (cross-classifications) by county and CWA. There are 36 demographic classifications that cross 3 age, 2 sex, 3 race, and 2 hispanic classifications. The R code automatically downloads data from the Census. This step also incorporates data from the US CDC’s Social Vulnerability Index.
        
    - Run: 2_create_base_census_dataset.R
    - Outputs: 
        - base_cwa_census_data.csv
        - base_county_census_data.csv

3.	**Create base survey dataset**. This step combines data from yearly public surveys in to one file. It also assigns respondents to counties by zipcode and estimates the measurement models to create the composite scales.
       
    - Run: 3_create_base_survey_dataset.R
    - Outputs:
        - base_survey_data.csv

4.	**Estimate cwa models**. This step estimates the multilevel regression models necessary to produce estimates of interest (tornado warning comprehension) for each CWA in the country. This is the first step in multilevel regression and postratification (MRP). Note that the models take a very long time to estimate. It may take hours/days to run this code.
       
    - Run: 4_estimate_cwa_models.R
    - Output:
        - cwa_models > cwa*.Rds files; 14 files, one file for each of the models

5.	**Estimate county models**. This step estimates the multilevel regression models necessary to produce estimates of interest (e.g., tornado warning comprehension) for each county in the country. This is the first step in multilevel regression and postratification (MRP). Note that the models take a very long time to estimate. It may take hours/days to run this code
       
    - Run: 5_estimate_county_models.R
    - Output:
        - county_models > county*.Rds files; 14 files, one file for each of the models

6. **Calculate cwa predictions**. This step uses the models above to predict the postratify estimates of interest (e.g., tornado warning comprehension) for each CWA in the country. This is the second step in multilevel regression and postratification (MRP).
       
    - Run: 6_calculate_cwa_predictions.R
    - Output:
        - cwa_estimates > cwa_estimates shape files

7. **Calculate county predictions**. This step uses the models above to predict the postratify estimates of interest (e.g., tornado warning comprehension) for each county in the country. This is the second step in multilevel regression and postratification (MRP).
       
    - Run: 7_calculate_county_predictions.R
    - Output:
        - county_estimates > county_estimates shape files

6.	**Create WxDash**. This step uses the files above to create the WxDash application.
      
    - Run: 8_create_wxdash.Rmd
    - Output:
        - https://crcm.shinyapps.io/WxDash/
                
While this repository does not include all of the `Output` files from the steps above, it does include the files necessary to accomplish Step 8, **Create WxDash** without executing Step 1-7. Those files are: `cwa_estimates` (a CWA shapefile with estimates), `county_estimates` (a CWA shapefile with estimates), and `base_survey_date.csv` (the Wx Survey data).
