/* file: ResultId.java */
/*******************************************************************************
* Copyright 2014-2016 Intel Corporation
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*******************************************************************************/

/**
 * @ingroup univariate_outlier_detection
 * @{
 */
package com.intel.daal.algorithms.univariate_outlier_detection;

/**
 * <a name="DAAL-CLASS-ALGORITHMS__UNIVARIATE_OUTLIER_DETECTION__RESULTID"></a>
 * @brief Available identifiers of results for the univariate outlier detection algorithm
 */
public final class ResultId {
    private int _value;

    public ResultId(int value) {
        _value = value;
    }

    public int getValue() {
        return _value;
    }

    private static final int weightsValue = 0;

    /** Univariate outlier detection results */
    public static final ResultId weights = new ResultId(weightsValue);
}
/** @} */
