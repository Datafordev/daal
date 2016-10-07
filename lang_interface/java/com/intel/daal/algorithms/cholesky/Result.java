/* file: Result.java */
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
 * @ingroup cholesky
 * @{
 */
package com.intel.daal.algorithms.cholesky;

import com.intel.daal.algorithms.Precision;
import com.intel.daal.data_management.data.HomogenNumericTable;
import com.intel.daal.data_management.data.NumericTable;
import com.intel.daal.services.DaalContext;

/**
 * <a name="DAAL-CLASS-ALGORITHMS__CHOLESKY__RESULT"></a>
 * @brief Results obtained with the compute() method of the Cholesky decomposition algorithm in the batch processing mode
 */
public final class Result extends com.intel.daal.algorithms.Result {
    /** @private */
    static {
        System.loadLibrary("JavaAPI");
    }

    public Result(DaalContext context) {
        super(context);
        this.cObject = cNewResult();
    }

    public Result(DaalContext context, long cAlgorithm, Precision prec, Method method) {
        super(context);
        if (cObject == 0) {
            cObject = cGetResult(cAlgorithm, prec.getValue(), method.getValue());
        }
    }

    /**
     * Returns the result of Cholesky decomposition
     * @param  id   Identifier of the result
     * @return Result that corresponds to the given identifier
     */
    public NumericTable get(ResultId id) {
        int idValue = id.getValue();
        if (idValue != ResultId.choleskyFactor.getValue()) {
            throw new IllegalArgumentException("id unsupported");
        }
        return new HomogenNumericTable(getContext(), cGetCholeskyFactor(cObject));
    }

    /**
     * Sets the final result of the Cholesky decomposition algorithm
     * @param id   Identifier of the result
     * @param val  Result that corresponds to the given identifier
     */
    public void set(ResultId id, NumericTable val) {
        int idValue = id.getValue();
        if (idValue != ResultId.choleskyFactor.getValue()) {
            throw new IllegalArgumentException("id unsupported");
        }
        cSetCholeskyFactor(cObject, val.getCObject());
    }

    private native long cNewResult();

    private native long cGetResult(long cAlgorithm, int prec, int method);

    private native long cGetCholeskyFactor(long cObject);

    private native void cSetCholeskyFactor(long cObject, long cNumericTable);
}
/** @} */
