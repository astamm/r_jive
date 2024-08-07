#' Angle based Joint and Individual Variation Explained
#'
#' Computes the JIVE decomposition.
#'
#' @param blocks A list of numeric matrices with same number of rows specifying
#'   the data blocks to be analyzed.
#' @param initial_signal_ranks An integer vector specifying the initial ranks
#'   for the signal matrices.
#' @param full A boolean specifying whether to store the full J, I and E
#'   matrices or solely their SVDs. Defaults to `TRUE`. Set to `FALSE` to save
#'   memory.
#' @param n_wedin_samples An integer value specifying the number of Wedin bound
#'   samples to draw. Defaults to `100L`.
#' @param n_rand_dir_samples An integer value specifying the number of random
#'   direction bound samples to draw. Defaults to `100L`.
#' @param joint_rank An integer valye specifying the rank of the joint space.
#'   Defaults to `NA` in which case it is estimated from the data.
#' @param joint_scores blabla. Defaults to `NULL` in which case they are
#'   estimated from the data.

#' @return A list containing the estimated JIVE decomposition. The list contains
#'  the following elements:
#'  - `joint_scores` A list of joint scores for each block.
#'  - `individual_scores` A list of individual scores for each block.
#'  - `joint` A list containing the joint decomposition.
#'  - `individual` A list containing the individual decomposition.
#'  - `noise` A list containing the noise decomposition.
#'  - `joint_rank` An integer specifying the rank of the joint space.
#'  - `individual_rank` A list of integers specifying the rank of the individual
#'  spaces.
#'  - `noise_rank` A list of integers specifying the rank of the noise spaces.
#'
#' @export
#' @examples
#' blocks <- sample_toy_data(n = 200, dx = 100, dy = 500)
#' initial_signal_ranks <- c(2L, 2L)
#' jive_decomp <- ajive(blocks, initial_signal_ranks)
#'
#' joint_scores <- jive_decomp[['joint_scores']]
#' J_1 <- jive_decomp$block_decomps[[1]][['joint']][['full']]
#' U_individual_2 <- jive_decomp$block_decomps[[2]][['individual']][['u']]
#' individual_rank_2 <- jive_decomp$block_decomps[[2]][['individual']][['rank']]
ajive <- function(blocks,
                  initial_signal_ranks,
                  full = TRUE,
                  n_wedin_samples = 100L,
                  n_rand_dir_samples = 100L,
                  joint_rank = NA,
                  joint_scores = NULL) {
    K <- length(blocks)

    if (K < 2) cli::cli_abort("`ajive` expects at least two data matrices.")

    if (sum(sapply(blocks, anyNA)) > 0)
        cli::cli_abort("Some of the blocks has missing data -- ajive expects full data matrices.")

    # blocks <- lapply(blocks, scale)

    # step 1: initial signal space extraction --------------------------------
    # initial estimate of signal space with SVD

    block_svd <- list()
    sv_thresholds <- rep(0, K)
    for (k in 1:K) {
        block_svd[[k]] <- get_svd(blocks[[k]])
        sv_thresholds[k] <- get_sv_threshold(
            singular_values = block_svd[[k]][['d']],
            rank = initial_signal_ranks[k]
        )
    }

    # step 2: joint sapce estimation -------------------------------------------------------------

    if (is.null(joint_scores)) {
        out <- get_joint_scores(
            blocks = blocks,
            block_svd = block_svd,
            initial_signal_ranks = initial_signal_ranks,
            sv_thresholds = sv_thresholds,
            n_wedin_samples = n_wedin_samples,
            n_rand_dir_samples = n_rand_dir_samples,
            joint_rank = joint_rank
        )
        joint_rank_sel_results <- out$rank_sel_results
        joint_scores <- out$joint_scores
        joint_rank <- out[['rank_sel_results']][['joint_rank_estimate']]
    } else {
        joint_rank_sel_results <- NULL
        joint_rank <- dim(joint_scores)[2]
    }

    # step 3: final decomposition -----------------------------------------------------

    block_decomps <- list()
    for (k in 1:K) {
        block_decomps[[k]] <- get_final_decomposition(
            X = blocks[[k]],
            joint_scores = joint_scores,
            sv_threshold = sv_thresholds[k]
        )
    }

    jive_decomposition <- list(block_decomps = block_decomps)
    jive_decomposition[['joint_scores']] <- joint_scores
    jive_decomposition[['joint_rank']] <- joint_rank

    jive_decomposition[['joint_rank_sel']] <- joint_rank_sel_results
    jive_decomposition
}

#' The singular value threshold.
#'
#' Computes the singluar value theshold for the data matrix (half way between
#' the rank and rank + 1 singluar value).
#'
#' @param singular_values Numeric. The singular values.
#' @param rank Integer. The rank of the approximation.
get_sv_threshold <- function(singular_values, rank) {
    .5 * (singular_values[rank] + singular_values[rank + 1])
}

#' Computes the joint scores.
#'
#' Estimate the joint rank with the wedin bound, compute the signal scores SVD,
#' double check each joint component.
#'
#' @param blocks List. A list of the data matrices.
#' @param block_svd List. The SVD of the data blocks.
#' @param initial_signal_ranks Numeric vector. Initial signal ranks estimates.
#' @param sv_thresholds Numeric vector. The singular value thresholds from the
#'   initial signal rank estimates.
#' @param n_wedin_samples Integer. Number of wedin bound samples to draw for
#'   each data matrix.
#' @param n_rand_dir_samples Integer. Number of random direction bound samples
#'   to draw.
#' @param joint_rank Integer or NA. User specified joint_rank. If NA will be
#'   estimated from data.
#'
#' @return Matrix. The joint scores.
get_joint_scores <- function(blocks,
                             block_svd,
                             initial_signal_ranks,
                             sv_thresholds,
                             n_wedin_samples = 1000,
                             n_rand_dir_samples = 1000,
                             joint_rank = NA) {
    if(is.na(n_wedin_samples) & is.na(n_rand_dir_samples) & is.na(joint_rank)){
        stop('at least one of n_wedin_samples, n_rand_dir_samples, or joint_rank must not be NA',
             call.=FALSE)
    }

    K <- length(blocks)
    n_obs <- dim(blocks[[1]])[1]

    # SVD of the signal scores matrix -----------------------------------------
    signal_scores <- list()
    for(k in 1:K){
        signal_scores[[k]] <- block_svd[[k]][['u']][, 1:initial_signal_ranks[k]]
    }

    M <- do.call(cbind, signal_scores)
    M_svd <- get_svd(M, rank=min(initial_signal_ranks))

    # estimate joint rank with wedin bound and random direction bound -------------------------------------------------------------

    rank_sel_results  <- list()
    rank_sel_results[['obs_svals']] <- M_svd[['d']]

    if(is.na(joint_rank)){

        # maybe comptue wedin bound
        if(!is.na(n_wedin_samples)){

            block_wedin_samples <- matrix(NA, K, n_wedin_samples)

            for(k in 1:K){
                block_wedin_samples[k, ] <- get_wedin_bound_samples(X=blocks[[k]],
                                                                    SVD=block_svd[[k]],
                                                                    signal_rank=initial_signal_ranks[k],
                                                                    num_samples=n_wedin_samples)
            }

            wedin_samples <-  K - colSums(block_wedin_samples)
            wedin_svsq_threshold <- stats::quantile(wedin_samples, .05)

            rank_sel_results[['wedin']] <- list(block_wedin_samples=block_wedin_samples,
                                                wedin_samples=wedin_samples,
                                                wedin_svsq_threshold=wedin_svsq_threshold)
        } else{
            wedin_svsq_threshold <- NA
        }

        # maybe compute random direction bound
        if(!is.na(n_rand_dir_samples)){

            rand_dir_samples <- get_random_direction_bound(n_obs=n_obs, dims=initial_signal_ranks, num_samples=n_rand_dir_samples)
            rand_dir_svsq_threshold <- stats::quantile(rand_dir_samples, .95)

            rank_sel_results[['rand_dir']] <- list(rand_dir_samples=rand_dir_samples,
                                                   rand_dir_svsq_threshold=rand_dir_svsq_threshold)

        } else {
            rand_dir_svsq_threshold <- NA
        }

        overall_sv_sq_threshold <- max(wedin_svsq_threshold, rand_dir_svsq_threshold, na.rm=TRUE)
        joint_rank_estimate <- sum(M_svd[['d']]^2 > overall_sv_sq_threshold)

        rank_sel_results[['overall_sv_sq_threshold']] <- overall_sv_sq_threshold
        rank_sel_results[['joint_rank_estimate']] <- joint_rank_estimate


    } else { # user provided joint rank
        joint_rank_estimate <- joint_rank
        rank_sel_results[['joint_rank_estimate']] <- joint_rank
    }


    # estimate joint score space ------------------------------------

    if(joint_rank_estimate >= 1){
        joint_scores <- M_svd[['u']][ , 1:joint_rank_estimate, drop=FALSE]

        # reconsider joint score space ------------------------------------
        # remove columns of joint_scores that have a
        # trivial projection from one of the data matrices

        to_remove <- c()
        for(k in 1:K){
            for(j in 1:joint_rank_estimate){

                score <- t(blocks[[k]]) %*% joint_scores[ , j]
                sv <- norm(score)

                if(sv < sv_thresholds[[k]]){
                    print(paste('removing column', j))
                    to_remove <- c(to_remove, j)
                    break
                }
            }

        }
        to_keep <- setdiff(1:joint_rank_estimate, to_remove)
        joint_rank <- length(to_keep)
        joint_scores <- joint_scores[ , to_keep, drop=FALSE]
    } else {
        joint_scores <- NA
    }


    list(joint_scores=joint_scores, rank_sel_results=rank_sel_results)
}

#' Computes the final JIVE decomposition.
#'
#' Computes X = J + I + E for a single data block and the respective SVDs.
#'
#'
#' @param X Matrix. The original data matrix.
#' @param joint_scores Matrix. The basis of the joint space (dimension n x joint_rank).
#' @param sv_threshold Numeric vector. The singular value thresholds from the initial signal rank estimates.
#' @param full Boolean. Do we compute the full J, I matrices or just the SVDs (set to FALSE to save memory)..
get_final_decomposition <- function(X, joint_scores, sv_threshold, full=TRUE){

    jive_decomposition <- list()
    jive_decomposition[['individual']] <- get_individual_decomposition(X, joint_scores, sv_threshold, full)
    jive_decomposition[['joint']] <- get_joint_decomposition(X, joint_scores, full)


    if(full){
        jive_decomposition[['noise']] <- X - (jive_decomposition[['joint']][['full']] +
                                                  jive_decomposition[['individual']][['full']])
    } else{
        jive_decomposition[['noise']] <- NA
    }

    jive_decomposition
}

#' Computes the individual matix for a data block.
#'
#' @param X Matrix. The original data matrix.
#' @param joint_scores Matrix. The basis of the joint space (dimension n x joint_rank).
#' @param sv_threshold Numeric vector. The singular value thresholds from the initial signal rank estimates.
#' @param full Boolean. Do we compute the full J, I matrices or just the SVD (set to FALSE to save memory).
get_individual_decomposition <- function(X, joint_scores, sv_threshold, full=TRUE){

    if(any(is.na(joint_scores))) {
        indiv_decomposition <- get_svd(X)
    } else{
        X_orthog <- (diag(dim(X)[1]) - joint_scores %*% t(joint_scores)) %*% X
        indiv_decomposition <- get_svd(X_orthog)
    }


    indiv_rank <- sum(indiv_decomposition[['d']] > sv_threshold)

    indiv_decomposition <- truncate_svd(decomposition=indiv_decomposition, rank=indiv_rank)

    if(full){
        indiv_decomposition[['full']] <- svd_reconstruction(indiv_decomposition)
    } else{
        indiv_decomposition[['full']] <- NA
    }

    indiv_decomposition[['rank']] <- indiv_rank
    indiv_decomposition
}

#' Computes the joint matix for a data block.
#'
#'
#' @param X Matrix. The original data matrix.
#' @param joint_scores Matrix. The basis of the joint space (dimension n x joint_rank).
#' @param full Boolean. Do we compute the full J, I matrices or just the SVD (set to FALSE to save memory).
get_joint_decomposition <- function(X, joint_scores, full=TRUE){

    if(any(is.na(joint_scores))) {
        joint_decomposition <- list(full= NA, rank=0, u=NA, d=NA, v=NA)
        return(joint_decomposition)
    }
    joint_rank <- dim(joint_scores)[2]
    J <-  joint_scores %*% t(joint_scores) %*% X

    joint_decomposition <- get_svd(J, joint_rank)

    if(full){
        joint_decomposition[['full']] <- J
    } else{
        joint_decomposition[['full']] <- NA
    }

    joint_decomposition[['rank']] <- joint_rank
    joint_decomposition

}
