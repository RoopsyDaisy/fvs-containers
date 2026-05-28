# Plan: Convert FVS to Database Input (DSNin + TreeSQL)

## Objective
Convert the FVS batch simulation from TREELIST file-based input to DSNin database input, matching the pattern used in official FVS test files where COMPUTE keyword works correctly.

## Background
- **Problem**: COMPUTE keyword causes 0 projectable trees when using TREELIST input
- **Discovery**: Official FVS tests use DSNin + TreeSQL (database input) with COMPUTE
- **Goal**: Enable COMPUTE/SPMCDBH for canopy cover output

## Implementation Steps

### Phase 1: Create FVS Input Database

#### 1.1 Database Schema
Create `FVS_Data.db` with two tables matching FVS expected schema:

**FVS_StandInit Table**
```sql
CREATE TABLE FVS_StandInit (
    Stand_CN TEXT PRIMARY KEY,
    Stand_ID TEXT,
    Variant TEXT,
    Inv_Year INTEGER,
    Groups TEXT,
    AddFiles TEXT,
    FVSKeywords TEXT,
    Latitude REAL,
    Longitude REAL,
    Region INTEGER,
    Forest INTEGER,
    District INTEGER,
    Compartment INTEGER,
    Location INTEGER,
    Ecoregion TEXT,
    PV_Code TEXT,
    PV_Ref_Code TEXT,
    Age INTEGER,
    Aspect REAL,
    Slope REAL,
    Elevation REAL,
    ElevFt REAL,
    Basal_Area_Factor REAL,
    Inv_Plot_Size REAL,
    Brk_DBH REAL,
    Num_Plots INTEGER,
    NonStk_Plots INTEGER,
    Sam_Wt REAL,
    Stk_Pcnt REAL,
    DG_Trans INTEGER,
    DG_Measure INTEGER,
    HTG_Trans INTEGER,
    HTG_Measure INTEGER,
    Mort_Trans INTEGER,
    Mort_Measure INTEGER,
    BA_Max REAL,
    SDI_Max REAL,
    Site_Species TEXT,
    Site_Index REAL,
    Model_Type INTEGER,
    Physio_Region INTEGER,
    Forest_Type INTEGER,
    State INTEGER,
    County INTEGER,
    Fuel_Model TEXT,
    Fuel_0_25_H REAL,
    Fuel_25_1_H REAL,
    Fuel_1_3_H REAL,
    Fuel_3_6_H REAL,
    Fuel_6_12_H REAL,
    Fuel_12_20_H REAL,
    Fuel_20_35_H REAL,
    Fuel_35_50_H REAL,
    Fuel_gt_50_H REAL,
    Fuel_0_25_S REAL,
    Fuel_25_1_S REAL,
    Fuel_1_3_S REAL,
    Fuel_3_6_S REAL,
    Fuel_6_12_S REAL,
    Fuel_12_20_S REAL,
    Fuel_20_35_S REAL,
    Fuel_35_50_S REAL,
    Fuel_gt_50_S REAL,
    Fuel_Litter REAL,
    Fuel_Duff REAL,
    Photo_Ref INTEGER,
    Photo_Code TEXT
);
```

**FVS_TreeInit Table**
```sql
CREATE TABLE FVS_TreeInit (
    Stand_CN TEXT,
    StandPlot_CN TEXT,
    Tree_CN TEXT PRIMARY KEY,
    Tree_ID INTEGER,
    Tree_Count REAL,
    History INTEGER,
    Species TEXT,
    DBH REAL,
    DG REAL,
    Ht REAL,
    HtTopK REAL,
    HtG REAL,
    CrRatio INTEGER,
    Damage1 INTEGER,
    Severity1 INTEGER,
    Damage2 INTEGER,
    Severity2 INTEGER,
    Damage3 INTEGER,
    Severity3 INTEGER,
    TreeValue INTEGER,
    Prescription INTEGER,
    Age INTEGER,
    Plot_ID INTEGER,
    Tree_Status INTEGER,
    TopoCode INTEGER,
    SitePrep INTEGER,
    FOREIGN KEY (Stand_CN) REFERENCES FVS_StandInit(Stand_CN)
);
```

#### 1.2 Python Script: Create Input Database
Create `src/fvs_tools/db_input.py`:

```python
"""
Create FVS input database from CSV data files.
Converts from TREELIST format to DSNin format.
"""
import sqlite3
import pandas as pd
from pathlib import Path

def create_fvs_input_db(
    stand_csv: Path,
    tree_csv: Path, 
    output_db: Path,
    stand_id: str
) -> None:
    """Create FVS_Data.db with FVS_StandInit and FVS_TreeInit tables."""
    
    conn = sqlite3.connect(output_db)
    
    # Create tables (schema above)
    # ... implementation
    
    # Load and transform stand data
    # ... implementation
    
    # Load and transform tree data  
    # ... implementation
    
    conn.close()
```

### Phase 2: Modify Keyword File Generator

#### 2.1 New Keyword Template
Replace TREELIST section with DSNin section:

**Before (TREELIST - current)**:
```
TREEFMT
(I4,I4,F8.3,I1,A3,F5.1,F5.1,2F5.1,F5.1,I1,6I2,2I1,I2,2I3,2I1,F3.0)

TREELIST          0         0         0         0         0         0         0
run.tre
```

**After (DSNin - new)**:
```
DATABASE
DSNin
FVS_Data.db
StandSQL
SELECT * FROM FVS_StandInit WHERE Stand_CN = '%StandID%'
EndSQL
TreeSQL
SELECT * FROM FVS_TreeInit WHERE Stand_CN = '%StandID%'
EndSQL
END
```

#### 2.2 Update keyword_generator.py
- Remove TREEFMT keyword (not needed with database input)
- Remove TREELIST keyword
- Add DSNin/StandSQL/TreeSQL block
- Keep existing STDIDENT, INVYEAR, etc.

### Phase 3: Update Library Modules

#### 3.1 Touched Modules
| Module | Change |
|--------|--------|
| `data_prep.py` | Add function to create FVS_Data.db |
| `keyword_generator.py` | Replace TREELIST with DSNin template |
| `runner.py` | Copy FVS_Data.db to run directory |
| `batch.py` | Orchestrate database creation |

#### 3.2 New Workflow
1. Load CSV data (existing)
2. Create FVS_Data.db with all stands (NEW)
3. Generate keyword files with DSNin reference (MODIFIED)
4. Run FVS (existing)
5. Extract results (existing)

### Phase 4: Testing

#### 4.1 Test Cases
1. Single stand (CARB_99) with DSNin - verify trees load
2. Single stand with COMPUTE - verify FVS_Compute populated
3. All 8 stands batch run with DSNin + COMPUTE
4. Compare output metrics to TREELIST baseline

#### 4.2 Expected Results
- FVS_Summary: Same TPA/BA/CCF as baseline
- FVS_Compute: Populated with canopy cover values
- Tree count: 24 trees for CARB_99

### Phase 5: Assignment Integration

#### 5.1 Updated Assignment 5 Deliverables
- Canopy cover from FVS_Compute table (via SPMCDBH function)
- Growth projections from FVS_Summary
- Calibration statistics from FVS_CalibStats

## Data Mapping

### Source CSV Columns (actual)

**FVS_Lubrecht_2023_FVS_StandInit.csv**:
```
STAND_ID, VARIANT, INV_YEAR, GROUPS, ADDFILES, FVSKEYWORDS, GIS_LINK, PROJECT_NAME,
LATITUDE, LONGITUDE, REGION, FOREST, DISTRICT, COMPARTMENT, LOCATION, ECOREGION,
PV_CODE, PV_REF_CODE, AGE, ASPECT, SLOPE, ELEVATION, ELEVFT, BASAL_AREA_FACTOR,
INV_PLOT_SIZE, BRK_DBH, NUM_PLOTS, NONSTK_PLOTS, SAM_WT, STK_PCNT, DG_TRANS,
DG_MEASURE, HTG_TRANS, HTG_MEASURE, MORT_MEASURE, MAX_BA, MAX_SDI, SITE_SPECIES,
SITE_INDEX, MODEL_TYPE, PHYSIO_REGION, FOREST_TYPE, STATE, COUNTY, FUEL_MODEL, ...
```

**FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv**:
```
STAND_ID, PLOT_ID, STANDPLOT_ID, TREE_ID, TAG_ID, TREE_COUNT, HISTORY, SPECIES,
DIAMETER, DIAMETER_HT, DG, HT, HTG, HTTOPK, HT_TO_LIVE_CROWN, CRRATIO, DAMAGE1,
SEVERITY1, DAMAGE2, SEVERITY2, DAMAGE3, SEVERITY3, DEFECT_CUBIC, DEFECT_BOARD,
TREEVALUE, PRESCRIPTION, AGE, SLOPE, ASPECT, PV_CODE, PV_REF_CODE, TOPOCODE, SITEPREP, ...
```

### Stand Data Mapping (CSV → FVS_StandInit)
| CSV Column | FVS_StandInit Column | Notes |
|------------|---------------------|-------|
| STAND_ID | Stand_CN | Use as primary key |
| STAND_ID | Stand_ID | Same value |
| VARIANT | Variant | "IE" for Inland Empire |
| INV_YEAR | Inv_Year | 2023 |
| LATITUDE | Latitude | |
| LONGITUDE | Longitude | |
| REGION | Region | |
| FOREST | Forest | |
| AGE | Age | |
| ASPECT | Aspect | |
| SLOPE | Slope | |
| ELEVFT | ElevFt | |
| BASAL_AREA_FACTOR | Basal_Area_Factor | |
| INV_PLOT_SIZE | Inv_Plot_Size | |
| NUM_PLOTS | Num_Plots | |
| SITE_SPECIES | Site_Species | |
| SITE_INDEX | Site_Index | |

### Tree Data Mapping (CSV → FVS_TreeInit)
| CSV Column | FVS_TreeInit Column | Notes |
|------------|---------------------|-------|
| STAND_ID | Stand_CN | Foreign key |
| PLOT_ID | Plot_ID | |
| TREE_ID | Tree_ID | |
| TREE_COUNT | Tree_Count | TPA expansion |
| HISTORY | History | |
| SPECIES | Species | 3-letter code |
| DIAMETER | DBH | Diameter in inches |
| DG | DG | Diameter growth |
| HT | Ht | Height in feet |
| HTG | HtG | Height growth |
| HTTOPK | HtTopK | |
| CRRATIO | CrRatio | Crown ratio |
| DAMAGE1 | Damage1 | |
| SEVERITY1 | Severity1 | |
| DAMAGE2 | Damage2 | |
| SEVERITY2 | Severity2 | |
| DAMAGE3 | Damage3 | |
| SEVERITY3 | Severity3 | |
| TREEVALUE | TreeValue | |
| PRESCRIPTION | Prescription | |
| AGE | Age | |

### Key Keyword File Structure (from NestedAddFile.key)
```
StdIdent
<stand_id>     <description>
StandCN
<stand_cn_value>
...
Database
DSNin
FVS_Data.db
StandSQL
SELECT * FROM FVS_StandInit WHERE Stand_CN = '%Stand_CN%'
EndSQL
TreeSQL
SELECT * FROM FVS_TreeInit WHERE Stand_CN = '%Stand_CN%'
EndSQL
END
```

Note: The `%Stand_CN%` placeholder is replaced by FVS with the value from the StandCN keyword.

## Validation Strategy

1. **Tree Loading**: Verify "PROJECTABLE TREE RECORDS" count matches input
2. **Summary Metrics**: Compare FVS_Summary to baseline (should match)
3. **Compute Table**: Verify FVS_Compute has rows with canopy cover values
4. **Canopy Cover Range**: Values should be 0-100 (percent)

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Schema mismatch | Use exact column names from FVS source code |
| SQL escaping | Use parameterized queries |
| Stand_CN format | Match format from working test files |
| Missing columns | Populate with NULL or defaults |

## Backout Plan
Keep existing TREELIST code path as fallback. Use CCF from FVS_Summary if database approach fails.

## Timeline Estimate
- Phase 1 (Database creation): 1-2 hours
- Phase 2 (Keyword modification): 30 min
- Phase 3 (Library updates): 1 hour
- Phase 4 (Testing): 1 hour
- Phase 5 (Integration): 30 min

**Total**: ~4-5 hours

## Files to Create/Modify

### New Files
- `src/fvs_tools/db_input.py` - Database creation module

### Modified Files
- `src/fvs_tools/keyword_generator.py` - DSNin template
- `src/fvs_tools/data_prep.py` - Call db_input
- `src/fvs_tools/runner.py` - Copy input database
- `src/fvs_tools/batch.py` - Orchestration

### Test Files
- `tests/test_db_input.py` - Unit tests for database creation
