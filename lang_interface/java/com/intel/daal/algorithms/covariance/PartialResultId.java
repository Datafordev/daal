/* file: PartialResultId.java */
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
 * @ingroup covariance
 * @{
 */
package com.intel.daal.algorithms.covariance;

/**
 * <a name="DAAL-CLASS-ALGORITHMS__COVARIANCE__PARTIALRESULTID"></a>
 * @brief Available identifiers of partial results of the correlation or variance-covariance matrix algorithm
 */
public final class PartialResultId {
    private int _value;

    public PartialResultId(int value) {
        _value = value;
    }

    public int getValue() {
        return _value;
    }

    private static final int nObservationsValue = 0;
    private static final int crossProductValue  = 1;
    private static final int sumValue           = 2;

    /** Number of observations processed so far */
    public static final PartialResultId nObservations = new PartialResultId(nObservationsValue);
    /** Cross-product matrix computed so far */
    public static final PartialResultId crossProduct  = new PartialResultId(crossProductValue);
    /** Vector of sums computed so far */
    public static final PartialResultId sum           = new PartialResultId(sumValue);
}
/** @} */
